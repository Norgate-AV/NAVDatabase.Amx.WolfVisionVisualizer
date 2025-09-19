MODULE_NAME='mWolfVisionVisualizer' (
                                        dev vdvObject,
                                        dev dvPort
                                    )

(***********************************************************)
#DEFINE USING_NAV_MODULE_BASE_CALLBACKS
#DEFINE USING_NAV_MODULE_BASE_PROPERTY_EVENT_CALLBACK
#DEFINE USING_NAV_MODULE_BASE_PASSTHRU_EVENT_CALLBACK
#DEFINE USING_NAV_STRING_GATHER_CALLBACK
#include 'NAVFoundation.ModuleBase.axi'
#include 'NAVFoundation.SocketUtils.axi'
#include 'NAVFoundation.StringUtils.axi'
#include 'NAVFoundation.TimelineUtils.axi'
#include 'NAVFoundation.ErrorLogUtils.axi'

/*
 _   _                       _          ___     __
| \ | | ___  _ __ __ _  __ _| |_ ___   / \ \   / /
|  \| |/ _ \| '__/ _` |/ _` | __/ _ \ / _ \ \ / /
| |\  | (_) | | | (_| | (_| | ||  __// ___ \ V /
|_| \_|\___/|_|  \__, |\__,_|\__\___/_/   \_\_/
                 |___/

MIT License

Copyright (c) 2023 Norgate AV Services Limited

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

(***********************************************************)
(*          DEVICE NUMBER DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_DEVICE

(***********************************************************)
(*               CONSTANT DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_CONSTANT

constant integer IP_PORT = 50915

constant long TL_DRIVE      = 1
constant long TL_IP_CHECK   = 2
constant long TL_HEARTBEAT  = 3

constant long TL_DRIVE_INTERVAL[] = { 200 }
constant long TL_IP_CHECK_INTERVAL[] = { 3000 }
constant long TL_HEARTBEAT_INTERVAL[] = { 20000 }

constant integer GET_POWER    = 1

constant integer POWER_STATE_ON  = 1
constant integer POWER_STATE_OFF = 2


(***********************************************************)
(*              DATA TYPE DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_TYPE

(***********************************************************)
(*               VARIABLE DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_VARIABLE

volatile _NAVModule module

volatile integer loop
volatile integer pollSequence = GET_POWER

volatile _NAVStateInteger powerState


(***********************************************************)
(*               LATCHING DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_LATCHING

(***********************************************************)
(*       MUTUALLY EXCLUSIVE DEFINITIONS GO BELOW           *)
(***********************************************************)
DEFINE_MUTUALLY_EXCLUSIVE

(***********************************************************)
(*        SUBROUTINE/FUNCTION DEFINITIONS GO BELOW         *)
(***********************************************************)
(* EXAMPLE: DEFINE_FUNCTION <RETURN_TYPE> <NAME> (<PARAMETERS>) *)
(* EXAMPLE: DEFINE_CALL '<NAME>' (<PARAMETERS>) *)

define_function SendString(char payload[]) {
    NAVErrorLog(NAV_LOG_LEVEL_DEBUG,
                NAVFormatStandardLogMessage(NAV_STANDARD_LOG_MESSAGE_TYPE_STRING_TO,
                                            dvPort,
                                            payload))
    send_string dvPort, payload
}


define_function SetPower(integer state) {
    switch (state) {
        case POWER_STATE_ON: {
            SendString("$01, $30, $01, $01")
        }
        case POWER_STATE_OFF: {
            SendString("$01, $30, $01, $00")
        }
    }
}


define_function SendQuery(integer query) {
    switch (query) {
        case GET_POWER: {
            SendString("$00, $10, $01, $0B")
        }
    }
}


define_function Drive() {
    loop++

    switch (loop) {
        case 5:
        case 10:
        case 15:
        case 20: {
            SendQuery(GET_POWER)
            return
        }
        case 30:{
            loop = 0
            return
        }
        default: {
            if (module.CommandBusy) {
                return
            }

            if (powerState.Required && (powerState.Required == powerState.Actual)) { powerState.Required = 0 }

            if (powerState.Required && (powerState.Required != powerState.Actual)) {
                SetPower(powerState.Required)

                module.CommandBusy = true
                wait 50 module.CommandBusy = false

                pollSequence = GET_POWER

                return
            }
        }
    }
}


define_function MaintainIpConnection() {
    if (module.Device.SocketConnection.IsConnected) {
        return
    }

    NAVClientSocketOpen(dvPort.PORT,
                        module.Device.SocketConnection.Address,
                        module.Device.SocketConnection.Port,
                        IP_TCP)
}


define_function CommunicationTimeOut(integer timeout) {
    cancel_wait 'TimeOut'

    module.Device.IsCommunicating = true
    UpdateFeedback()

    wait (timeout * 10) 'TimeOut' {
        module.Device.IsCommunicating = false
        UpdateFeedback()
    }
}


define_function Reset() {
    module.Device.SocketConnection.IsConnected = false
    module.Device.IsCommunicating = false
    module.Device.IsInitialized = false
    UpdateFeedback()

    NAVTimelineStop(TL_HEARTBEAT)
    NAVTimelineStop(TL_DRIVE)
}


define_function NAVModulePropertyEventCallback(_NAVModulePropertyEvent event) {
    switch (event.Name) {
        case NAV_MODULE_PROPERTY_EVENT_IP_ADDRESS: {
            module.Device.SocketConnection.Address = event.Args[1]
            module.Device.SocketConnection.Port = IP_PORT
            NAVTimelineStart(TL_IP_CHECK,
                            TL_IP_CHECK_INTERVAL,
                            TIMELINE_ABSOLUTE,
                            TIMELINE_REPEAT)
        }
    }
}


define_function NAVModulePassthruEventCallback(_NAVModulePassthruEvent event) {
    if (event.Device != vdvObject) {
        return
    }

    SendString(event.Payload)
}


#IF_DEFINED USING_NAV_STRING_GATHER_CALLBACK
define_function NAVStringGatherCallback(_NAVStringGatherResult args) {
    stack_var char data[NAV_MAX_BUFFER]
    stack_var char delimiter[NAV_MAX_CHARS]
    stack_var integer bytes[128]
    stack_var integer x

    data = args.Data
    delimiter = args.Delimiter

    for (x = 1; x <= 128; x++) {
        bytes[x] = get_buffer_char(module.RxBuffer.Data)
    }

    switch (bytes[1] band $80) {
        case $80: { powerState.Actual = POWER_STATE_ON }
        case $00: { powerState.Actual = POWER_STATE_OFF }
        default: { powerState.Actual = POWER_STATE_OFF }
    }

    UpdateFeedback()
}
#END_IF


define_function UpdateFeedback() {
    [vdvObject, NAV_IP_CONNECTED]	= (module.Device.SocketConnection.IsConnected)
    [vdvObject, DEVICE_COMMUNICATING] = (module.Device.IsCommunicating)
    [vdvObject, DATA_INITIALIZED] = (module.Device.IsInitialized)

    [vdvObject, POWER_FB]    = (powerState.Actual == POWER_STATE_ON)
}


(***********************************************************)
(*                STARTUP CODE GOES BELOW                  *)
(***********************************************************)
DEFINE_START {
    NAVModuleInit(module)
    create_buffer dvPort, module.RxBuffer.Data
}

(***********************************************************)
(*                THE EVENTS GO BELOW                      *)
(***********************************************************)
DEFINE_EVENT

data_event[dvPort] {
    online: {
        if (data.device.number != 0) {
            NAVCommand(data.device, "'SET BAUD 115200 N 8 1 485 DISABLE'")
            NAVCommand(data.device, "'B9MOFF'")
            NAVCommand(data.device, "'CHARD-0'")
            NAVCommand(data.device, "'CHARDM-0'")
            NAVCommand(data.device, "'HSOFF'")
        }

        if (data.device.number == 0) {
            module.Device.SocketConnection.IsConnected = true
            UpdateFeedback()
        }

        NAVTimelineStart(TL_DRIVE,
                        TL_DRIVE_INTERVAL,
                        TIMELINE_ABSOLUTE,
                        TIMELINE_REPEAT)
    }
    offline: {
        if (data.device.number == 0) {
            NAVClientSocketClose(data.device.port)
            Reset()
        }
    }
    onerror: {
        if (data.device.number == 0) {
            Reset()
        }
    }
    string: {
        [vdvObject, DATA_INITIALIZED] = true
        [vdvObject, DEVICE_COMMUNICATING] = true
        UpdateFeedback()

        CommunicationTimeOut(30)

        NAVErrorLog(NAV_LOG_LEVEL_DEBUG,
                    NAVFormatStandardLogMessage(NAV_STANDARD_LOG_MESSAGE_TYPE_STRING_FROM,
                                                data.device,
                                                data.text))

        select {
            active(data.text == "$80, $10, $0B"): {
                powerState.Actual = POWER_STATE_OFF
                UpdateFeedback()
            }
            active (true): {
                NAVStringGather(module.RxBuffer, "$00, $10, $81, $0B")
            }
        }
    }
}


data_event[vdvObject] {
    command:{
        stack_var _NAVSnapiMessage message

        NAVParseSnapiMessage(data.text, message)

        switch (message.Header){
            case 'POWER': {
                switch (message.Parameter[1]) {
                    case 'ON': {
                        powerState.Required = POWER_STATE_ON
                        Drive()
                    }
                    case 'OFF': {
                        powerState.Required = POWER_STATE_OFF
                        Drive()
                    }
                }
            }
            case 'FREEZE': {
                switch (message.Parameter[1]) {
                    case 'ON':      { SendString("$01, $56, $01, $01") }
                    case 'OFF':     { SendString("$01, $56, $01, $00") }
                    case 'TOGGLE':  { SendString("$01, $56, $01, $02") }
                }
            }
            case 'AUTO_FOCUS': {
                switch (message.Parameter[1]) {
                    case 'ON':      { SendString("$01, $31, $01, $01") }
                    case 'OFF':     { SendString("$01, $31, $01, $00") }
                    case 'TOGGLE':  { SendString("$01, $31, $01, $02") }
                }
            }
            case 'AUTO_IRIS': {
                switch (message.Parameter[1]) {
                    case 'ON':      { SendString("$01, $32, $01, $01") }
                    case 'OFF':     { SendString("$01, $32, $01, $00") }
                    case 'TOGGLE':  { SendString("$01, $32, $01, $02") }
                }
            }
            case 'ANGLE': {
                switch (message.Parameter[1]) {
                    case 'OFF':     { SendString("$01, $83, $01, $00") }
                    case 'TOGGLE':  { SendString("$01, $83, $01, $02") }
                }
            }
        }
    }
}


channel_event[vdvObject, 0]{
    on: {
        switch (channel.channel){
            case ZOOM_OUT:      { SendString("$01, $20, $01, $11") }
            case ZOOM_IN:       { SendString("$01, $20, $01, $12") }
            case FOCUS_NEAR:    { SendString("$01, $21, $01, $12") }
            case FOCUS_FAR:     { SendString("$01, $21, $01, $11") }
            case AUTO_FOCUS:    { SendString("$01, $31, $01, $02") }
            case PWR_ON: {
                powerState.Required = POWER_STATE_ON
                Drive()
            }
            case PWR_OFF: {
                powerState.Required = POWER_STATE_OFF
                Drive()
            }
        }
    }
    off: {
        switch (channel.channel){
            case ZOOM_OUT:      { SendString("$01, $2F, $01, $00") }
            case ZOOM_IN:       { SendString("$01, $2F, $01, $00") }
            case FOCUS_NEAR:    { SendString("$01, $2F, $01, $00") }
            case FOCUS_FAR:     { SendString("$01, $2F, $01, $00") }
        }
    }
}


timeline_event[TL_IP_CHECK] { MaintainIPConnection() }


timeline_event[TL_DRIVE] { Drive() }


(***********************************************************)
(*                     END OF PROGRAM                      *)
(*        DO NOT PUT ANY CODE BELOW THIS COMMENT           *)
(***********************************************************)

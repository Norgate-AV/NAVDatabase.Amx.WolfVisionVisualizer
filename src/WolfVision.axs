MODULE_NAME='WolfVision'(DEV vdvControl, DEV dvRS232)
#include 'NAVFoundation.ModuleBase.axi'
#include 'NAVFoundation.SocketUtils.axi'

DEFINE_CONSTANT
INTEGER chnZoomDEC = 158
INTEGER chnZoomINC = 159
INTEGER chnMotor[] = {
    158,159
}

constant integer IP_PORT = 50915
constant long TL_IP_CLIENT_CHECK = 1
constant long TL_DRIVE    = 2

constant integer GET_POWER    = 1

constant integer REQUIRED_POWER_ON    = 1
constant integer REQUIRED_POWER_OFF    = 2

constant integer ACTUAL_POWER_ON    = 1
constant integer ACTUAL_POWER_OFF    = 2

DEFINE_VARIABLE
INTEGER DEBUG = 0
volatile char cIPAddress[15]
volatile integer iClientConnected

volatile integer iSemaphore
volatile char cRxBuffer[NAV_MAX_BUFFER]

volatile integer iLoop
volatile integer iPollSequence = GET_POWER

volatile long ltIPClientCheck[] = { 3000 }
volatile long ltDrive[] = { 200 }

volatile integer iRequiredPower

volatile integer iActualPower

volatile integer iActualPowerInitialized

volatile integer iCommandLockOut

define_function SendString(char cParam[]) {
    //NAVLog(NAVFormatStandardLogMessage(NAV_STANDARD_LOG_MESSAGE_TYPE_STRING_TO, dvRS232, cParam))
    send_string 0, NAVFormatStandardLogMessage(NAV_STANDARD_LOG_MESSAGE_TYPE_STRING_TO, data.device, cParam)
    send_string dvRS232,"cParam"
}

define_function SetPower(integer iParam) {
    switch (iParam) {
    case REQUIRED_POWER_ON: {
        SendString("$01,$30,$01,$01")
    }
    case REQUIRED_POWER_OFF: {
        SendString("$01,$30,$01,$00")
    }
    }
}

define_function SendQuery(integer iParam) {
    switch (iParam) {
    case GET_POWER: {
        SendString("$00,$10,$01,$0B")
    }
    }
}

define_function Drive() {
    iLoop++
    switch (iLoop) {
    case 1:
    case 6:
    case 11:
    case 16:
    case 21:
    case 50: { SendQuery(GET_POWER); iLoop = 1; return }
    default: {
        if (iCommandLockOut) return

        if (iRequiredPower && (iRequiredPower == iActualPower)) { iRequiredPower = 0; return }

        if (iRequiredPower && (iRequiredPower <> iActualPower)) {
        SetPower(iRequiredPower); iCommandLockOut = true; wait 50 iCommandLockOut = false; iPollSequence = GET_POWER; return
        }
    }
    }
}

define_function TimeOut() {
    [vdvControl,DEVICE_COMMUNICATING] = true
    cancel_wait 'CommsTimeOut'
    wait 300 'CommsTimeOut' { [vdvControl,DEVICE_COMMUNICATING] = false }
}

define_function Process() {
    stack_var char cTemp[NAV_MAX_BUFFER]
    iSemaphore = true
    while (length_array(cRxBuffer) && NAVContains(cRxBuffer,"$00,$10,$81,$0B")) {
    cTemp = remove_string(cRxBuffer,"$00,$10,$81,$0B",1)
    if (length_array(cTemp)) {
        stack_var integer iData[128]
        stack_var integer x
        for (x = 1; x <= 128; x++) {
        iData[x] = get_buffer_char(cRxBuffer)
        }

        switch (iData[1] band $80) {
        case $80: { iActualPower = ACTUAL_POWER_ON }
        case $00: { iActualPower = ACTUAL_POWER_OFF }
        }
    }
    }

    iSemaphore = false
}

define_start {
    create_buffer dvRS232,cRxBuffer
}

DEFINE_EVENT DATA_EVENT[dvRS232]{
    ONLINE:{
        if (data.device.number <> 0) SEND_COMMAND dvRS232, 'SET BAUD 115200 N 8 1 485 DISABLE'
        else {
        iClientConnected = true
        NAVLog("'WOLFVISION_CLIENT_CONNECTED<true>'")
        [vdvControl,DATA_INITIALIZED] = true
        [vdvControl,DEVICE_COMMUNICATING] = true
        }

        timeline_create(TL_DRIVE,ltDrive,length_array(ltDrive),timeline_absolute,timeline_repeat)
    }
    offline: {
        if (data.device.number == 0) {
        iClientConnected = false
        NAVLog("'WOLFVISION_CLIENT_CONNECTED<false>'")
        NAVClientSocketClose(data.device.port)
        }
    }
    onerror: {
        if (data.device.number == 0) {
        iClientConnected = false
        NAVLog("'WOLFVISION_CLIENT_CONNECTED<false>'")
        //NAVClientSocketClose(data.device.port)
        }
    }
    STRING:{
        //NAVLog(NAVFormatStandardLogMessage(NAV_STANDARD_LOG_MESSAGE_TYPE_STRING_FROM, data.device, data.text))
        send_string 0, NAVFormatStandardLogMessage(NAV_STANDARD_LOG_MESSAGE_TYPE_STRING_FROM, data.device, data.text)
        [vdvControl,DATA_INITIALIZED] = true
        TimeOut()
        if (!iSemaphore) {
            Process()
        }
    }
}

DEFINE_EVENT DATA_EVENT[vdvControl]{
    COMMAND:{
        NAVLog(NAVFormatStandardLogMessage(NAV_STANDARD_LOG_MESSAGE_TYPE_COMMAND_FROM, data.device, data.text))
        SWITCH(NAVStripCharsFromRight(REMOVE_STRING(DATA.TEXT,'-',1),1)){
            CASE 'DEBUG':   DEBUG = ATOI(DATA.TEXT);
            case 'PROPERTY': {
                switch (NAVStripCharsFromRight(REMOVE_STRING(DATA.TEXT,',',1),1)) {
                case 'IP_ADDRESS': {
                    cIPAddress = data.text
                    timeline_create(TL_IP_CLIENT_CHECK,ltIPClientCheck,length_array(ltIPClientCheck),TIMELINE_ABSOLUTE,TIMELINE_REPEAT)
                }
                }
            }
            CASE 'POWER':{
                SWITCH(DATA.TEXT){
                    CASE 'ON':    iRequiredPower = REQUIRED_POWER_ON; Drive()
                    CASE 'OFF':    iRequiredPower = REQUIRED_POWER_OFF; Drive()
                }
            }
            CASE 'FREEZE':{
                SWITCH(DATA.TEXT){
                    CASE 'ON':    SendString("$01,$56,$01,$01")
                    CASE 'OFF':    SendString("$01,$56,$01,$00")
                    CASE 'TOGGLE':    SendString("$01,$56,$01,$02")
                }
            }
            CASE 'AUTO_FOCUS':{
                SWITCH(DATA.TEXT){
                    CASE 'ON':    SendString("$01,$31,$01,$01")
                    CASE 'OFF':    SendString("$01,$31,$01,$00")
                    CASE 'TOGGLE':    SendString("$01,$31,$01,$02")
                }
            }
            CASE 'AUTO_IRIS':{
                SWITCH(DATA.TEXT){
                    CASE 'ON':    SendString("$01,$32,$01,$01")
                    CASE 'OFF':    SendString("$01,$32,$01,$00")
                    CASE 'TOGGLE':    SendString("$01,$32,$01,$02")
                }
            }
            CASE 'ANGLE':{
                SWITCH(DATA.TEXT){
                    CASE 'TOGGLE':    SendString("$01,$83,$01,$02")
                    CASE 'OFF':        SendString("$01,$83,$01,$00")
                }
            }
        }
    }
}

DEFINE_EVENT CHANNEL_EVENT[vdvControl,0]{
    ON:{
        //NAVLog("'CHANNEL_ON_RECEIVED<',itoa(channel.channel),'>'")
        SWITCH(CHANNEL.CHANNEL){
            CASE chnZoomDEC: SendString("$01,$20,$01,$11")
            CASE chnZoomINC: SendString("$01,$20,$01,$12")
            case FOCUS_NEAR: { SendString("$01,$21,$01,$12") }
            case FOCUS_FAR: { SendString("$01,$21,$01,$11") }
            case AUTO_FOCUS: { SendString("$01,$31,$01,$02") }
            case PWR_ON: { iRequiredPower = REQUIRED_POWER_ON; Drive() }
            case PWR_OFF: { iRequiredPower = REQUIRED_POWER_OFF; Drive() }
        }
    }
    OFF:{
        //NAVLog("'CHANNEL_OFF_RECEIVED<',itoa(channel.channel),'>'")
        SWITCH(CHANNEL.CHANNEL){
            CASE chnZoomDEC: SendString("$01,$2F,$01,$00")
            CASE chnZoomINC: SendString("$01,$2F,$01,$00")
            case FOCUS_NEAR: { SendString("$01,$2F,$01,$00") }
            case FOCUS_FAR: { SendString("$01,$2F,$01,$00") }
        }
    }
}


define_function MaintainIPConnection() {
    //NAVLog("'WOLFVISION_IP_MAINTENANCE'")
    if (!iClientConnected) {
    NAVClientSocketOpen(dvRS232.port,cIPAddress,IP_PORT,IP_TCP)
    }
}

define_event timeline_event[TL_IP_CLIENT_CHECK] { MaintainIPConnection() }

define_event timeline_event[TL_DRIVE] { Drive() }

timeline_event[TL_NAV_FEEDBACK] {
    [vdvControl,POWER_FB]    = (iActualPower == ACTUAL_POWER_ON)
}



OPT PREPROCESS
OPT LARGE

MODULE  'commodities',
        'icon',
        'amigalib/argarray',
        'libraries/commodities',
        'amigalib/lists',
        'intuition/screens',
        'intuition/intuition',
        'intuition/intuitionbase',
        'libraries/gadtools',
        'graphics/clip',
        'graphics/layers',
        'graphics/text', 
        'exec/ports',
        'exec/execbase',
        'exec/io',
        'exec/lists',
        'exec/nodes',
        'exec/tasks',
        'exec/libraries',
        'devices/timer',
        'gadtools',
        'intuition',
        'layers',
        'dos',
        'dos/dos',
        'dos/dosextens',
        'dos/dostags',
        'dos/datetime',
        'dos/filehandler',
        'screennotify', 'libraries/screennotify',
        'wb',
        'workbench/startup',
        'workbench/workbench',
        'layers',
        'graphics/layers',
        'devices/inputevent',
        'other/ecode'


ENUM    ERR_NONE=0,
        ERR_KICKSTART,
        ERR_NOINTUITION,
        ERR_NOCOMMODITY,
        ERR_NOICON,
        ERR_ARG_TT,
        ERR_CREATE_BROKER_PORT,
        ERR_CREATE_BROKER,
        ERR_CXERR,
        ERR_ECODE,
        ERR_SIGNAL,
        ERR_TIMER_OPEN,
        ERR_TIMER_MP,
        ERR_TIMER_IO,
        ERR_NO_PUBSCREEN

ENUM    POS_NONE,
        POS_RIGHT_UP=1,
        POS_RIGHT_DOWN,
        POS_LEFT_UP,
        POS_LEFT_DOWN,
        POS_LEFT,
        POS_RIGHT,
        POS_UP,
        POS_DOWN

CONST OS_32_VERSION=47 -> OS 3.2

ENUM    EVENT_LEFTBUTTON=1

DEF    bLeftButtonIsDown=FALSE

DEF     exec=NIL:PTR TO execbase,  
        intuition=NIL:PTR TO intuitionbase


DEF broker_mp=NIL:PTR TO mp, 
    broker=NIL, cxmsg=NIL,
    filter=NIL, sender=NIL, translate=NIL,
    bCommodityActive=TRUE,
    cocustom=NIL, signal=-1, cxobjsignal, cxsigflag, task, cosignal

DEF ie:PTR TO inputevent
DEF previewWnd=NIL:PTR TO window, bPreviewWindIsHidden=TRUE

DEF timer_tr=NIL:PTR TO timerequest, 
    timer_msgport=NIL:PTR TO mp,
    timer_sig, second, micro

DEF pubScreen=NIL:PTR TO screen,
    activeWindowOnScreen=NIL:PTR TO window

DEF wndDownButton=NIL:PTR TO window,
    wndUpButton=NIL:PTR TO window,
    wndDownX=-1, wndDownY=-1,
    wndUpX=-1, wndUpY=-1


PROC main() HANDLE

    DEF ttypes=NIL,
        iCxPriority=0,
        cxfunc=NIL

    IF (KickVersion(OS_32_VERSION)=FALSE) THEN Raise(ERR_KICKSTART)

    exec:=execbase
    intuition:=intuitionbase
    cxbase:=NIL
    iconbase:=NIL

    IF (intuition.libnode.version <46 ) THEN Raise(ERR_NOINTUITION)
    IF (cxbase:=OpenLibrary('commodities.library', 39))=NIL THEN Raise(ERR_NOCOMMODITY)
    IF (iconbase:=OpenLibrary('icon.library', 39))=NIL THEN Raise(ERR_NOICON)

    IF (ttypes:=argArrayInit())=NIL THEN Raise(ERR_ARG_TT)
    iCxPriority:=argInt(ttypes, 'CX_PRIORITY', 0)


    broker_mp:=CreateMsgPort()
    IF broker_mp=NIL THEN Raise(ERR_CREATE_BROKER_PORT)
    cxsigflag:=Shl(1, broker_mp.sigbit)


    broker:=CxBroker([NB_VERSION, 0,
                   'GoSnap',   -> String to identify this broker
                   'GoSnap 1.0 by Krzysztof Donat',
                   'Snaps windows to screen edges',
                    NBU_UNIQUE, 0, iCxPriority, 0,
                    broker_mp, 0]:newbroker, NIL)
    
    IF broker=NIL THEN Raise(ERR_CREATE_BROKER)


    -> CxCustom() takes two arguments, a pointer to the custom function and an
    -> ID.  Commodities Exchange will assign that ID to any CxMsg passed to the
    -> custom function.
    -> E-Note: eCodeCxCustom() protects an E function so you can use it as a
    ->         CX custom function
    IF NIL=(cxfunc:=eCodeCxCustom({cxFunction})) THEN Raise(ERR_ECODE)
    cocustom:=CxCustom(cxfunc, 0)
    AttachCxObj(broker, cocustom)

    -> Allocate a signal bit for the signal CxObj
    signal:=AllocSignal(-1)
    IF signal=-1 THEN Raise(ERR_SIGNAL)

    -> Set up the signal mask
    cxobjsignal:=Shl(1, signal)
    cxsigflag:=cxsigflag OR cxobjsignal

    -> CxSignal takes two arguments, a pointer to the task to signal (normally
    -> the commodity) and the number of the signal bit the commodity acquired
    -> to signal with.
    task:=FindTask(NIL)
    cosignal:=CxSignal(task, signal)
    AttachCxObj(cocustom, cosignal)
    ActivateCxObj(broker, TRUE)


    /*   timer  init */ 
    timer_msgport:=CreateMsgPort()    -> create port for timer
    IF (timer_msgport = NIL) THEN Raise(ERR_TIMER_MP)
    
    timer_tr:=CreateIORequest(timer_msgport,SIZEOF timerequest)
    IF (timer_tr = NIL) THEN Raise (ERR_TIMER_IO)

    IF (OpenDevice('timer.device',UNIT_MICROHZ,timer_tr,0)<>NIL) THEN Raise (ERR_TIMER_OPEN)

    timer_sig:=Shl(1, timer_msgport.sigbit)
    cxsigflag:=cxsigflag OR timer_sig

    timer_tr.io.command:=TR_ADDREQUEST     ->
    timer_tr.time.secs:=3                   -> set timer request
    timer_tr.time.micro:=0 ->1000000-micro     ->
    SendIO(timer_tr)

    /*  end timer */

    pubScreen:=LockPubScreen('Workbench')
    IF pubScreen=NIL THEN Raise(ERR_NO_PUBSCREEN)


    previewWnd:= OpenW (0,0, 200, 400, 
                        0, -> idcmp
                        0, -> wflg
                        NIL, ->title
                        pubScreen, -> screen
                        $F, -> open in workbench
                        NIL, -> gadgets
                        [WA_HIDDEN, TRUE, NIL] )

    processMessages()

    EXCEPT DO

        IF previewWnd THEN CloseW(previewWnd)
        IF pubScreen THEN UnlockPubScreen(NIL, pubScreen)

        IF timer_tr 
            CloseDevice(timer_tr)
            DeleteIORequest(timer_tr)
        ENDIF
    
        IF timer_msgport THEN  DeleteMsgPort(timer_msgport)
        

        
        IF signal<>-1 THEN FreeSignal(signal)

        IF broker THEN DeleteCxObjAll(broker)
        IF broker_mp
            WHILE cxmsg:=GetMsg(broker_mp) DO ReplyMsg(cxmsg)
            DeleteMsgPort(broker_mp)
        ENDIF


        IF ttypes       THEN argArrayDone()
        IF iconbase     THEN CloseLibrary(iconbase)
        IF cxbase       THEN CloseLibrary(cxbase)


        IF exception THEN WriteF('GoSnap error (\d) - ', exception)
        SELECT exception
            CASE ERR_ARG_TT;        WriteF('could not init tooltype arg array\n')
            CASE ERR_KICKSTART;     WriteF('needs Kickstart v47+ (OS 3.2 or higher)\n')	
            CASE ERR_NOINTUITION;   WriteF('needs intuition.library v47+\n')
            CASE ERR_NOCOMMODITY;   WriteF('needs commodities.library v39+\n')
            CASE ERR_NOICON;        WriteF('needs icon.library v39+\n')
            CASE ERR_CREATE_BROKER_PORT; WriteF('could not create broker port\n')
            CASE ERR_CREATE_BROKER; WriteF('could not create broker - another instance of GoSnap is already running\n')
            CASE ERR_CXERR;         WriteF('could not activate broker\n')
            CASE ERR_ECODE;         WriteF('ran out of memory in eCodeCxCustom()\n')
            CASE ERR_SIGNAL;        WriteF('could not allocate signal\n')
            CASE ERR_TIMER_IO;      WriteF('could not allocate timer IO request\n')
            CASE ERR_TIMER_MP;      WriteF('could not create timer port\n')
            CASE ERR_TIMER_OPEN;    WriteF('could not open timer.device\n')
            CASE ERR_NO_PUBSCREEN;  WriteF('could not lock public screen \aWorkbench\a\n')
        
        
        ENDSELECT

ENDPROC


PROC processMessages()

    DEF  cxmsgid=0,  cxmsgtype=0, 
    _abort=FALSE, mouseX=-1, mouseY=-1, sigrcvd, snapPosition=POS_NONE
    


    DEF done=FALSE

    REPEAT

        sigrcvd:=Wait(SIGBREAKF_CTRL_C OR cxsigflag)
            
        WHILE cxmsg:=GetMsg(broker_mp)
            cxmsgid:=CxMsgID(cxmsg)
            cxmsgtype:=CxMsgType(cxmsg)
            ReplyMsg(cxmsg)
            
                SELECT cxmsgid
                    CASE CXCMD_DISABLE
                      ->      WriteF('CXCMD_DISABLE\n')
                            ActivateCxObj(broker, FALSE)
                            bCommodityActive:=FALSE
                    CASE CXCMD_ENABLE
                        ->    WriteF('CXCMD_ENABLE\n')
                            ActivateCxObj(broker, TRUE)
                            bCommodityActive:=TRUE
                    CASE CXCMD_KILL
                          ->      WriteF('CXCMD_KILL\n')
                            done:=TRUE
                        
                 ENDSELECT
        ENDWHILE

        IF sigrcvd AND SIGBREAKF_CTRL_C 
            done:=TRUE
        ENDIF 

        IF sigrcvd AND timer_sig 
            
            ->DisplayBeep(0)
/*
               IF bPreviewWindIsHidden=FALSE
                    HideWindow(previewWnd)
                    bPreviewWindIsHidden:=TRUE
                ELSE
                    ShowWindow(previewWnd, WINDOW_FRONTMOST)
                    bPreviewWindIsHidden:=FALSE
                ENDIF 
*/
            timer_tr.io.command:=TR_ADDREQUEST     ->
            timer_tr.time.secs:=3                   -> set timer request
            timer_tr.time.micro:=0 ->1000000-micro     ->
            SendIO(timer_tr)
        ENDIF

        IF sigrcvd AND cxobjsignal 
    
            ->WriteF('Got Signal\n')


            ->IF (ie.class=IECLASS_RAWMOUSE) THEN WriteF ('IECLASS_RAWMOUSE\n')
            ->IF (ie.class=IECLASS_POINTERPOS) THEN WriteF ('IECLASS_POINTERPOS\n')


            IF ((ie.qualifier AND IEQUALIFIER_LEFTBUTTON) = IEQUALIFIER_LEFTBUTTON)
                IF (bLeftButtonIsDown=FALSE)

                    bLeftButtonIsDown:=TRUE

                    activeWindowOnScreen:=findActiveWindow()
                    IF activeWindowOnScreen
                        IF (isResizableWindow(activeWindowOnScreen))
                            wndDownButton:=activeWindowOnScreen
                            wndDownX:=wndDownButton.leftedge
                            wndDownY:=wndDownButton.topedge

                            wndUpButton:=NIL
                            ->WriteF(' - Resizable window: \s', activeWindowOnScreen.title)
                        
                        ENDIF
                    ENDIF    
                    
                ENDIF
            ELSE
                IF (bLeftButtonIsDown) 
                    
                    bLeftButtonIsDown:=FALSE

                    activeWindowOnScreen:=findActiveWindow()
                    
                    
                    IF (activeWindowOnScreen AND (wndDownButton=activeWindowOnScreen))
                       -> IF (isResizableWindow(activeWindowOnScreen))
                            IF wndDownButton
                                wndUpButton:=activeWindowOnScreen
                                wndUpX:=wndUpButton.leftedge
                                wndUpY:=wndUpButton.topedge
                            
                                ->WriteF(' - Resizable window: \s', activeWindowOnScreen.title)
                            ENDIF
                        ->ENDIF
                    ENDIF
                    
                ENDIF
            ENDIF

            -> jeśli wskaxniki okna up i down sa ustawione i takie same
            -> tzn ze mamy złapane okno skalowalne 
            IF (wndDownButton  AND (wndDownButton=wndUpButton))
                
                IF (wndDownX<>wndUpX) OR (wndDownY<>wndUpY)
                    
                    ->WriteF ('mam przesuniecie okna \s \n', wndDownButton.title)

                    snapPosition:=getSnapPosision(pubScreen.mousex, pubScreen.mousey)

                    IF (snapPosition<>POS_NONE)

                        snapWindow(wndDownButton, snapPosition)

                    ENDIF
                        

                    wndDownButton:=NIL
                    wndUpButton:=NIL
                    wndDownX:=-1
                    wndUpX:=-1
                    wndDownY:=-1
                    wndUpY:=-1

                    
                ENDIF    
            ENDIF



           
        ENDIF
    UNTIL done


    AbortIO(timer_tr)            -> end the last timer request
    WaitIO(timer_tr)    

ENDPROC

PROC snapWindow(wnd:PTR TO window, snapPosition)

DEF scrTop, scrLeft, scrRight, scrBottom

DEF newWidth, newHeight, newX, newY    

    SELECT snapPosition
        CASE POS_LEFT_UP

            newWidth:=pubScreen.width /2
            newHeight:=(pubScreen.height - pubScreen.barheight) /2
            
            ->WriteF('0 newWidth: \d newHeight: \d\n', newWidth, newHeight)

            ->WriteF('1 minWidth: \d maxWidth: \d minHeigth: \d maxHeight: \d\n', 
            ->        $FFFF AND wnd.minwidth, $FFFF AND wnd.maxwidth, $FFFF AND wnd.minheight, $FFFF AND wnd.maxheight)
            IF newWidth > ($FFFF AND wnd.maxwidth)  THEN newWidth:=($FFFF AND wnd.maxwidth)
            IF newWidth < ($FFFF AND wnd.minwidth)  THEN newWidth:=($FFFF AND wnd.minwidth)
            IF newHeight > ($FFFF AND wnd.maxheight) THEN newHeight:=($FFFF AND wnd.maxheight)
            IF newHeight < ($FFFF AND wnd.minheight) THEN newHeight:=($FFFF AND wnd.minheight)

            ->WriteF('2 newWidth: \d newHeight: \d\n', newWidth, newHeight)

            newX:=pubScreen.leftedge
            newY:=pubScreen.topedge+pubScreen.barheight +1
            
            moveWindowToSnap(wnd, newX, newY, newWidth, newHeight)

        CASE POS_RIGHT_UP

            newWidth:=pubScreen.width /2
            newHeight:=(pubScreen.height - pubScreen.barheight) /2
            
            IF newWidth > ($FFFF AND wnd.maxwidth)  THEN newWidth:=($FFFF AND wnd.maxwidth)
            IF newWidth < ($FFFF AND wnd.minwidth)  THEN newWidth:=($FFFF AND wnd.minwidth)
            IF newHeight > ($FFFF AND wnd.maxheight) THEN newHeight:=($FFFF AND wnd.maxheight)
            IF newHeight < ($FFFF AND wnd.minheight) THEN newHeight:=($FFFF AND wnd.minheight)
            
            newX:=pubScreen.width - newWidth
            newY:=pubScreen.topedge+pubScreen.barheight +1
            
            moveWindowToSnap(wnd, newX, newY, newWidth, newHeight)
            
        CASE POS_LEFT_DOWN
            
            newWidth:=pubScreen.width /2
            newHeight:=((pubScreen.height - pubScreen.barheight) /2)-1

            IF newWidth > ($FFFF AND wnd.maxwidth)  THEN newWidth:=($FFFF AND wnd.maxwidth)
            IF newWidth < ($FFFF AND wnd.minwidth)  THEN newWidth:=($FFFF AND wnd.minwidth)
            IF newHeight > ($FFFF AND wnd.maxheight) THEN newHeight:=($FFFF AND wnd.maxheight)
            IF newHeight < ($FFFF AND wnd.minheight) THEN newHeight:=($FFFF AND wnd.minheight)
            
            newX:=pubScreen.leftedge
            newY:=pubScreen.height - newHeight
            
            moveWindowToSnap(wnd, newX, newY, newWidth, newHeight)

        CASE POS_RIGHT_DOWN

            newWidth:=pubScreen.width /2
            newHeight:=((pubScreen.height - pubScreen.barheight) /2)-1

            IF newWidth > ($FFFF AND wnd.maxwidth)  THEN newWidth:=($FFFF AND wnd.maxwidth)
            IF newWidth < ($FFFF AND wnd.minwidth)  THEN newWidth:=($FFFF AND wnd.minwidth)
            IF newHeight > ($FFFF AND wnd.maxheight) THEN newHeight:=($FFFF AND wnd.maxheight)
            IF newHeight < ($FFFF AND wnd.minheight) THEN newHeight:=($FFFF AND wnd.minheight)
            
            newX:=pubScreen.width - newWidth 
            newY:=pubScreen.height-newHeight

            moveWindowToSnap(wnd, newX, newY, newWidth, newHeight)

        CASE POS_LEFT
            
            newWidth:=pubScreen.width /2
            newHeight:=(pubScreen.height - pubScreen.barheight)-1

            IF newWidth > ($FFFF AND wnd.maxwidth)  THEN newWidth:=($FFFF AND wnd.maxwidth)
            IF newWidth < ($FFFF AND wnd.minwidth)  THEN newWidth:=($FFFF AND wnd.minwidth)
            IF newHeight > ($FFFF AND wnd.maxheight) THEN newHeight:=($FFFF AND wnd.maxheight)
            IF newHeight < ($FFFF AND wnd.minheight) THEN newHeight:=($FFFF AND wnd.minheight)
            
            newX:=pubScreen.leftedge
            newY:=pubScreen.topedge+pubScreen.barheight

            moveWindowToSnap(wnd, newX, newY, newWidth, newHeight)

        CASE POS_RIGHT

            newWidth:=pubScreen.width /2
            newHeight:=(pubScreen.height - pubScreen.barheight)-1

            IF newWidth > ($FFFF AND wnd.maxwidth)  THEN newWidth:=($FFFF AND wnd.maxwidth)
            IF newWidth < ($FFFF AND wnd.minwidth)  THEN newWidth:=($FFFF AND wnd.minwidth)
            IF newHeight > ($FFFF AND wnd.maxheight) THEN newHeight:=($FFFF AND wnd.maxheight)
            IF newHeight < ($FFFF AND wnd.minheight) THEN newHeight:=($FFFF AND wnd.minheight)
            
            newX:=pubScreen.width-newWidth
            newY:=pubScreen.topedge+pubScreen.barheight

            moveWindowToSnap(wnd, newX, newY, newWidth, newHeight)

        CASE POS_UP
            
            
            newWidth:=pubScreen.width
            newHeight:=(pubScreen.height - pubScreen.barheight)-1

            IF newWidth > ($FFFF AND wnd.maxwidth)  THEN newWidth:=($FFFF AND wnd.maxwidth)
            IF newWidth < ($FFFF AND wnd.minwidth)  THEN newWidth:=($FFFF AND wnd.minwidth)
            IF newHeight > ($FFFF AND wnd.maxheight) THEN newHeight:=($FFFF AND wnd.maxheight)
            IF newHeight < ($FFFF AND wnd.minheight) THEN newHeight:=($FFFF AND wnd.minheight)
            
            newX:=pubScreen.leftedge
            newY:=pubScreen.topedge+pubScreen.barheight+1

            moveWindowToSnap(wnd, newX, newY, newWidth, newHeight)

        CASE POS_DOWN

            newWidth:=pubScreen.width 
            newHeight:=((pubScreen.height - pubScreen.barheight)/2)-1
            
            IF newWidth > ($FFFF AND wnd.maxwidth)  THEN newWidth:=($FFFF AND wnd.maxwidth)
            IF newWidth < ($FFFF AND wnd.minwidth)  THEN newWidth:=($FFFF AND wnd.minwidth)
            IF newHeight > ($FFFF AND wnd.maxheight) THEN newHeight:=($FFFF AND wnd.maxheight)
            IF newHeight < ($FFFF AND wnd.minheight) THEN newHeight:=($FFFF AND wnd.minheight)
            
            newX:=pubScreen.leftedge
            newY:=pubScreen.height - newHeight
            
            moveWindowToSnap(wnd, newX, newY, newWidth, newHeight)

    ENDSELECT


ENDPROC

PROC moveWindowToSnap(wnd:PTR TO window, newX, newY, newWidth, newHeight)

    IF (wnd=NIL) THEN RETURN
    
        IF (isWindowsStillOpen(wnd))
            ChangeWindowBox( wnd, newX, newY, newWidth, newHeight )
            WindowToFront(wnd)
        ENDIF
    
ENDPROC


PROC isWindowsStillOpen(wnd:PTR TO window)

    DEF w:PTR TO window

    w:=pubScreen.firstwindow

    WHILE w
        
        IF (w=wnd) THEN RETURN TRUE
        
        w:= w.nextwindow

    ENDWHILE
    
    RETURN FALSE
ENDPROC

-> The custom function for the custom CxObject.  Any code for a custom CxObj
-> must be short and sweet because it runs as part of the input.device task.
PROC cxFunction(cxm, co)

  -> Get the struct InputEvent associated with this CxMsg.  Unlike the
  -> InputEvent extracted from a CxSender's CxMsg, this is a *REAL* input
  -> event, be careful with it.
  ie:=CxMsgData(cxm)


    IF (ie.class=IECLASS_RAWMOUSE)
    
      ->IF (ie.code =  IECODE_LBUTTON)

        -> WriteF('Mouse event\n')
      ->WriteF('Mouse event\n')
            DivertCxMsg(cxm, co, co)
      ->ENDIF

    ENDIF

ENDPROC


PROC findActiveWindow()

    DEF _wnd:PTR TO window

    Forbid()
    _wnd:=pubScreen.firstwindow

    WHILE _wnd
        
        IF ((_wnd.flags AND WFLG_WINDOWACTIVE ) = WFLG_WINDOWACTIVE )
            Permit()
            RETURN _wnd

        ENDIF

        _wnd:= _wnd.nextwindow

    ENDWHILE
    Permit()
    RETURN NIL

ENDPROC


/* Funkcja weryfikuje czy okno jest oknem Worlbencha, ale nie głownym*/
PROC isWorkbenchWindow(wnd:PTR TO window)

    IF wnd=NIL THEN RETURN FALSE

    IF (((wnd.flags AND WFLG_WBENCHWINDOW ) = WFLG_WBENCHWINDOW ) AND (wnd.parent <> NIL ))
    
        -> zabezpieczenie na TexEdit, Find, które ma ustawioną flagę WFLG_WBENCHWINDOW
            IF wnd.userport
                IF wnd.userport.sigtask
                    IF wnd.userport.sigtask.ln
                        IF wnd.userport.sigtask.ln.name
                            ->WriteF('TASKNAME: \s, title: \s\n', wnd.userport.sigtask.ln.name, wnd.title)
                            IF (StrCmp(wnd.userport.sigtask.ln.name, 'Workbench')) 
                                RETURN TRUE
                            ENDIF
                        ENDIF
                    ENDIF
                ENDIF
            ENDIF
    ENDIF

    RETURN FALSE

ENDPROC


/* Funkcja weryfikuje czy okno jest oknem Worlbencha, ale nie głownym*/
PROC isResizableWindow(wnd:PTR TO window)

    IF wnd=NIL THEN RETURN FALSE

    IF ((wnd.flags AND WFLG_SIZEGADGET ) = WFLG_SIZEGADGET )
     
        RETURN TRUE
    
    ENDIF

    RETURN FALSE

ENDPROC

PROC getSnapPosision(x, y)

    DEF snapPosition=POS_NONE
    DEF screenWidth, screenHeight
    DEF screenLeft, screenTop, screenRight, screenBottom


    DEF iMargines=40

    screenWidth:=pubScreen.width
    screenHeight:=pubScreen.height

    screenLeft:=pubScreen.leftedge
    screenTop:=pubScreen.topedge
    
    ->WriteF('x,y: \d \d \n', x, y)

    IF (x < iMargines) AND (y < iMargines)  THEN           
        RETURN POS_LEFT_UP

    IF (x > (screenWidth-iMargines)) AND (y < iMargines) THEN               
        RETURN POS_RIGHT_UP

    IF (x < iMargines) AND (y > (screenHeight-iMargines)) THEN              
        RETURN POS_LEFT_DOWN

    IF (x > (screenWidth-iMargines)) AND (y > (screenHeight-iMargines)) THEN 
        RETURN POS_RIGHT_DOWN

    IF (x < iMargines) THEN                                         
        RETURN POS_LEFT
    
    IF (x > (screenWidth-iMargines)) THEN 
        RETURN POS_RIGHT
    
    IF (y < iMargines) THEN   
        RETURN POS_UP
    
    IF (y > (screenHeight-iMargines)) THEN  
        RETURN POS_DOWN
    
    RETURN POS_NONE    

ENDPROC 
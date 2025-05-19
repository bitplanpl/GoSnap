
MODULE  'commodities',
        'icon',
        'amigalib/argarray',
        'libraries/commodities',
        'intuition/screens',
        'intuition/intuition',
        'intuition/intuitionbase',
        'exec/ports',
        'exec/libraries',
        'intuition',
        'dos',
        'dos/dos',
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

CONST OS_314_VERSION=46 -> OS 3.1.4

ENUM    EVENT_LEFTBUTTON=1

DEF     bLeftButtonIsDown=FALSE,
        bOS4=FALSE,
        intuition=NIL:PTR TO intuitionbase,
        iSnapMargin=10, 
        bKeepMenuBar=TRUE, 
        bShowSnapArea=FALSE


DEF broker_mp=NIL:PTR TO mp, 
    broker=NIL, cxmsg=NIL, sig_broker,
    bCommodityActive=TRUE,
    cocustom=NIL, signal=-1, cxobjsignal, task, cosignal

DEF ie:PTR TO inputevent


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

    IF (KickVersion(OS_314_VERSION)=FALSE) THEN Raise(ERR_KICKSTART)
    IF KickVersion(51)  THEN bOS4:=TRUE

    intuition:=intuitionbase
    cxbase:=NIL
    iconbase:=NIL

    IF (intuition.libnode.version <46 ) THEN Raise(ERR_NOINTUITION)
    IF (cxbase:=OpenLibrary('commodities.library', 39))=NIL THEN Raise(ERR_NOCOMMODITY)
    IF (iconbase:=OpenLibrary('icon.library', 39))=NIL THEN Raise(ERR_NOICON)

    IF (ttypes:=argArrayInit())=NIL THEN Raise(ERR_ARG_TT)

    iCxPriority:=argInt(ttypes, 'CX_PRIORITY', 0)
    IF iCxPriority > 127  THEN iCxPriority := 127
    IF iCxPriority < -128 THEN iCxPriority := -127

    iSnapMargin:=argInt(ttypes, 'SNAP_MARGIN', 9)
    IF iSnapMargin > 100 THEN iSnapMargin :=100
    IF iSnapMargin < 2   THEN iSnapMargin := 2

    
    IF  StrCmp('YES', TrimStr(UpperStr(argString(ttypes, 'KEEP_MENUBAR', 'YES'))),3)
        bKeepMenuBar:=TRUE
    ELSE
        bKeepMenuBar:=FALSE
    ENDIF

    IF  StrCmp('YES', TrimStr(UpperStr(argString(ttypes, 'SHOW_SNAPAREA_AT_START', 'NO'))),3)
        bShowSnapArea:=TRUE
    ENDIF

    ->WriteF('SNAP_MARGIN = \d\n', iSnapMargin)

    broker_mp:=CreateMsgPort()
    IF broker_mp=NIL THEN Raise(ERR_CREATE_BROKER_PORT)
    sig_broker:=Shl(1, broker_mp.sigbit)


    broker:=CxBroker([NB_VERSION, 0,
                   'GoSnap',   -> String to identify this broker
                   'GoSnap v0.13 by Krzysztof Donat',
                   'Snaps windows to screen edges.',
                    NBU_UNIQUE, 0, iCxPriority, 0,
                    broker_mp, 0]:newbroker, NIL)
    
    IF broker=NIL THEN Raise(ERR_CREATE_BROKER)


    -> CxCustom() takes two arguments, a pointer to the custom function and an
    -> ID.  Commodities Exchange will assign that ID to any CxMsg passed to the
    -> custom function.
    -> E-Note: eCodeCxCustom() protects an E function so you can use it as a
    ->         CX custom function
    cxfunc:=eCodeCxCustom({cxFunction})
    IF cxfunc=NIL THEN   Raise(ERR_ECODE)
    
    cocustom:=CxCustom(cxfunc, 0)
    AttachCxObj(broker, cocustom)

    -> Allocate a signal bit for the signal CxObj
    signal:=AllocSignal(-1)
    IF signal=-1 THEN Raise(ERR_SIGNAL)

    -> Set up the signal mask
    cxobjsignal:=Shl(1, signal)

    -> CxSignal takes two arguments, a pointer to the task to signal (normally
    -> the commodity) and the number of the signal bit the commodity acquired
    -> to signal with.
    task:=FindTask(NIL)
    cosignal:=CxSignal(task, signal)
    AttachCxObj(cocustom, cosignal)
    ActivateCxObj(broker, TRUE)

    pubScreen:=LockPubScreen('Workbench')
    IF pubScreen=NIL THEN Raise(ERR_NO_PUBSCREEN)


    IF bShowSnapArea THEN showSnapAreaAtStart()

    processMessages()

    EXCEPT DO

        IF pubScreen THEN UnlockPubScreen(NIL, pubScreen)

        
        IF signal<>-1 THEN FreeSignal(signal)

        IF broker THEN DeleteCxObjAll(broker)
        IF broker_mp
            WHILE cxmsg:=GetMsg(broker_mp) DO ReplyMsg(cxmsg)
            DeleteMsgPort(broker_mp)
        ENDIF


        IF ttypes       THEN argArrayDone()
        IF iconbase     THEN CloseLibrary(iconbase)
        IF cxbase       THEN CloseLibrary(cxbase)


        SELECT exception
            CASE ERR_ARG_TT;        showError(exception, 'could not init tooltype arg array\n')
            CASE ERR_KICKSTART;     showError(exception, 'needs Kickstart v46+ (OS 3.1.4 or higher)\n')	
            CASE ERR_NOINTUITION;   showError(exception, 'needs intuition.library v46+\n')
            CASE ERR_NOCOMMODITY;   showError(exception, 'needs commodities.library v39+\n')
            CASE ERR_NOICON;        showError(exception, 'needs icon.library v39+\n')
            CASE ERR_CREATE_BROKER_PORT; showError(exception, 'could not create broker port\n')
            CASE ERR_CREATE_BROKER; showError(exception, 'could not create broker - another instance of GoSnap is already running\n')
            CASE ERR_CXERR;         showError(exception, 'could not activate broker\n')
            CASE ERR_ECODE;         showError(exception, 'ran out of memory in eCodeCxCustom()\n')
            CASE ERR_SIGNAL;        showError(exception, 'could not allocate signal\n')
            CASE ERR_NO_PUBSCREEN;  showError(exception, 'could not lock public screen \aWorkbench\a\n')
        
        
        ENDSELECT

ENDPROC

PROC showError(excp, strError)

    DEF str

    str:=String(150)

    IF (str)

        StringF(str, 'GoSnap error (\d) - \s', excp, strError )

        IF wbmessage=NIL
            WriteF(str)
        ELSE
            EasyRequestArgs(
                NIL,[SIZEOF easystruct,0,'GoSnap',str,'Oh, no...'],0,0)
        ENDIF
        DisposeLink(str)
    ENDIF

ENDPROC

PROC processMessages()

    DEF  cxmsgid=0,  cxmsgtype=0, 
    sigrcvd, snapPosition=POS_NONE, done=FALSE

    REPEAT

        sigrcvd:=Wait(SIGBREAKF_CTRL_C OR sig_broker OR cxobjsignal)

        IF sigrcvd AND sig_broker 

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

        ENDIF

        IF sigrcvd AND SIGBREAKF_CTRL_C 
            done:=TRUE
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
                        ->IF (isResizableWindow(activeWindowOnScreen))
                            wndDownButton:=activeWindowOnScreen
                            wndDownX:=wndDownButton.leftedge
                            wndDownY:=wndDownButton.topedge

                            wndUpButton:=NIL
                            ->WriteF(' - Resizable window: \s', activeWindowOnScreen.title)
                        
                        ->ENDIF
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


ENDPROC

PROC snapWindow(wnd:PTR TO window, snapPosition)


    DEF newWidth, newHeight, newX, newY, iMenuBar=0, iGap=1

    IF (bKeepMenuBar = TRUE)
         iMenuBar   := pubScreen.barheight
         iGap       := 1
    ELSE
        iMenuBar    := 0
        iGap        := 0
    ENDIF

    SELECT snapPosition
        CASE POS_LEFT_UP

            newWidth:=pubScreen.width /2
            newHeight:=(pubScreen.height - iMenuBar) /2
            
            ->WriteF('0 newWidth: \d newHeight: \d\n', newWidth, newHeight)

            ->WriteF('1 minWidth: \d maxWidth: \d minHeigth: \d maxHeight: \d\n', 
            ->        $FFFF AND wnd.minwidth, $FFFF AND wnd.maxwidth, $FFFF AND wnd.minheight, $FFFF AND wnd.maxheight)
            IF newWidth > ($FFFF AND wnd.maxwidth)  THEN newWidth:=($FFFF AND wnd.maxwidth)
            IF newWidth < ($FFFF AND wnd.minwidth)  THEN newWidth:=($FFFF AND wnd.minwidth)
            IF newHeight > ($FFFF AND wnd.maxheight) THEN newHeight:=($FFFF AND wnd.maxheight)
            IF newHeight < ($FFFF AND wnd.minheight) THEN newHeight:=($FFFF AND wnd.minheight)

            ->WriteF('2 newWidth: \d newHeight: \d\n', newWidth, newHeight)

            newX:=pubScreen.leftedge
            newY:=pubScreen.topedge+iMenuBar + iGap
            
            moveWindowToSnap(wnd, newX, newY, newWidth, newHeight)

        CASE POS_RIGHT_UP

            newWidth:=pubScreen.width /2
            newHeight:=(pubScreen.height - iMenuBar) /2
            
            IF newWidth > ($FFFF AND wnd.maxwidth)  THEN newWidth:=($FFFF AND wnd.maxwidth)
            IF newWidth < ($FFFF AND wnd.minwidth)  THEN newWidth:=($FFFF AND wnd.minwidth)
            IF newHeight > ($FFFF AND wnd.maxheight) THEN newHeight:=($FFFF AND wnd.maxheight)
            IF newHeight < ($FFFF AND wnd.minheight) THEN newHeight:=($FFFF AND wnd.minheight)
            
            newX:=pubScreen.width - newWidth
            newY:=pubScreen.topedge+iMenuBar +iGap
            
            moveWindowToSnap(wnd, newX, newY, newWidth, newHeight)
            
        CASE POS_LEFT_DOWN
            
            newWidth:=pubScreen.width /2
            newHeight:=((pubScreen.height - iMenuBar) /2)-iGap

            IF newWidth > ($FFFF AND wnd.maxwidth)  THEN newWidth:=($FFFF AND wnd.maxwidth)
            IF newWidth < ($FFFF AND wnd.minwidth)  THEN newWidth:=($FFFF AND wnd.minwidth)
            IF newHeight > ($FFFF AND wnd.maxheight) THEN newHeight:=($FFFF AND wnd.maxheight)
            IF newHeight < ($FFFF AND wnd.minheight) THEN newHeight:=($FFFF AND wnd.minheight)
            
            newX:=pubScreen.leftedge
            newY:=pubScreen.height - newHeight
            
            moveWindowToSnap(wnd, newX, newY, newWidth, newHeight)

        CASE POS_RIGHT_DOWN

            newWidth:=pubScreen.width /2
            newHeight:=((pubScreen.height - iMenuBar) /2)-iGap

            IF newWidth > ($FFFF AND wnd.maxwidth)  THEN newWidth:=($FFFF AND wnd.maxwidth)
            IF newWidth < ($FFFF AND wnd.minwidth)  THEN newWidth:=($FFFF AND wnd.minwidth)
            IF newHeight > ($FFFF AND wnd.maxheight) THEN newHeight:=($FFFF AND wnd.maxheight)
            IF newHeight < ($FFFF AND wnd.minheight) THEN newHeight:=($FFFF AND wnd.minheight)
            
            newX:=pubScreen.width - newWidth 
            newY:=pubScreen.height-newHeight

            moveWindowToSnap(wnd, newX, newY, newWidth, newHeight)

        CASE POS_LEFT
            
            newWidth:=pubScreen.width /2
            newHeight:=(pubScreen.height - iMenuBar)-iGap

            IF newWidth > ($FFFF AND wnd.maxwidth)  THEN newWidth:=($FFFF AND wnd.maxwidth)
            IF newWidth < ($FFFF AND wnd.minwidth)  THEN newWidth:=($FFFF AND wnd.minwidth)
            IF newHeight > ($FFFF AND wnd.maxheight) THEN newHeight:=($FFFF AND wnd.maxheight)
            IF newHeight < ($FFFF AND wnd.minheight) THEN newHeight:=($FFFF AND wnd.minheight)
            
            newX:=pubScreen.leftedge
            newY:=pubScreen.topedge+iMenuBar

            moveWindowToSnap(wnd, newX, newY, newWidth, newHeight)

        CASE POS_RIGHT

            newWidth:=pubScreen.width /2
            newHeight:=(pubScreen.height - iMenuBar)-iGap

            IF newWidth > ($FFFF AND wnd.maxwidth)  THEN newWidth:=($FFFF AND wnd.maxwidth)
            IF newWidth < ($FFFF AND wnd.minwidth)  THEN newWidth:=($FFFF AND wnd.minwidth)
            IF newHeight > ($FFFF AND wnd.maxheight) THEN newHeight:=($FFFF AND wnd.maxheight)
            IF newHeight < ($FFFF AND wnd.minheight) THEN newHeight:=($FFFF AND wnd.minheight)
            
            newX:=pubScreen.width-newWidth
            newY:=pubScreen.topedge+iMenuBar

            moveWindowToSnap(wnd, newX, newY, newWidth, newHeight)

        CASE POS_UP
            
            
            newWidth:=pubScreen.width
            newHeight:=(pubScreen.height - iMenuBar)-iGap

            IF newWidth > ($FFFF AND wnd.maxwidth)  THEN newWidth:=($FFFF AND wnd.maxwidth)
            IF newWidth < ($FFFF AND wnd.minwidth)  THEN newWidth:=($FFFF AND wnd.minwidth)
            IF newHeight > ($FFFF AND wnd.maxheight) THEN newHeight:=($FFFF AND wnd.maxheight)
            IF newHeight < ($FFFF AND wnd.minheight) THEN newHeight:=($FFFF AND wnd.minheight)
            
            newX:=pubScreen.leftedge
            newY:=pubScreen.topedge+iMenuBar+iGap

            moveWindowToSnap(wnd, newX, newY, newWidth, newHeight)

        CASE POS_DOWN

            newWidth:=pubScreen.width 
            newHeight:=((pubScreen.height - iMenuBar)/2)-iGap
            
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
            IF bOS4 THEN WindowToFront(wnd)
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
            DivertCxMsg(cxm, co, co)
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


PROC getSnapPosision(x, y)

    DEF screenWidth, screenHeight
    DEF screenLeft, screenTop

    screenWidth:=pubScreen.width
    screenHeight:=pubScreen.height

    screenLeft:=pubScreen.leftedge
    screenTop:=pubScreen.topedge
    
    ->WriteF('x,y: \d \d \n', x, y)

    IF (x < iSnapMargin) AND (y < iSnapMargin)  THEN           
        RETURN POS_LEFT_UP

    IF (x > (screenWidth-iSnapMargin)) AND (y < iSnapMargin) THEN               
        RETURN POS_RIGHT_UP

    IF (x < iSnapMargin) AND (y > (screenHeight-iSnapMargin)) THEN              
        RETURN POS_LEFT_DOWN

    IF (x > (screenWidth-iSnapMargin)) AND (y > (screenHeight-iSnapMargin)) THEN 
        RETURN POS_RIGHT_DOWN

    IF (x < iSnapMargin) THEN                                         
        RETURN POS_LEFT
    
    IF (x > (screenWidth-iSnapMargin)) THEN 
        RETURN POS_RIGHT
    
    IF (y < iSnapMargin) THEN   
        RETURN POS_UP
    
    IF (y > (screenHeight-iSnapMargin)) THEN  
        RETURN POS_DOWN
    
    RETURN POS_NONE    

ENDPROC 

PROC showSnapAreaAtStart()

DEF winTopLeft=NIL, winTopRight=NIL, winDownLeft=NIL, winDownRight=NIL,
    winTop=NIL, winDown=NIL, winLeft=NIL, winRight=NIL,
    x,y, szer, wys

    -> topLeft
    x:=0
    y:=0
    szer:=iSnapMargin
    wys:=iSnapMargin
    winTopLeft:=drawSnapObszar(x, y, szer, wys, 1)

    x:=pubScreen.width-iSnapMargin
    y:=0
    szer:=iSnapMargin
    wys:=iSnapMargin
    winTopRight:=drawSnapObszar(x, y, szer, wys, 1)

    x:=0
    y:=pubScreen.height-iSnapMargin
    szer:=iSnapMargin
    wys:=iSnapMargin
    winDownLeft:=drawSnapObszar(x, y, szer, wys, 1)

    x:=pubScreen.width-iSnapMargin
    y:=pubScreen.height-iSnapMargin
    szer:=iSnapMargin
    wys:=iSnapMargin
    winDownRight:=drawSnapObszar(x, y, szer, wys, 1)

    x:=0+iSnapMargin
    y:=0
    szer:=pubScreen.width - (2*iSnapMargin)
    wys:=iSnapMargin
    winTop:=drawSnapObszar(x, y, szer, wys, 3)
    
    x:=0+iSnapMargin
    y:=pubScreen.height - iSnapMargin
    szer:=pubScreen.width - (2*iSnapMargin)
    wys:=iSnapMargin
    winDown:=drawSnapObszar(x, y, szer, wys, 3)

    x:=0
    y:=0+iSnapMargin
    szer:=iSnapMargin
    wys:=pubScreen.height-(2*iSnapMargin)
    winLeft:=drawSnapObszar(x, y, szer, wys, 3)

    x:=pubScreen.width-iSnapMargin
    y:=0+iSnapMargin
    szer:=iSnapMargin
    wys:=pubScreen.height-(2*iSnapMargin)
    winRight:=drawSnapObszar(x, y, szer, wys, 3)

    Delay(50)

    IF winTopLeft   THEN CloseW(winTopLeft)
    IF winTopRight    THEN CloseW(winTopRight)
    IF winDownLeft    THEN CloseW(winDownLeft)
    IF winDownRight   THEN CloseW(winDownRight)
    IF winTop    THEN CloseW(winTop)
    IF winDown    THEN CloseW(winDown)
    IF winLeft   THEN CloseW(winLeft)
    IF winRight    THEN CloseW(winRight)


ENDPROC


PROC drawSnapObszar(x, y, szer, wys, kol)

    DEF win=NIL:PTR TO window

    ->win := OpenW(x,y,wid,hgt,idcmp,wflgs,title,scrn,sflgs,gads,tags=NIL) 
    win := OpenW(x,y,szer,wys,NIL,WFLG_BORDERLESS,NIL,NIL,1,NIL,NIL)
    Box(0,0, szer, wys, kol)


ENDPROC win

version:
CHAR '$VER: GoSnap 0.13 (18.05.2025) http://www.bitplan.pl/gosnap',0


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

CONST OS_314_VERSION=46,    -> OS 3.1.4
      OS_4_VERSION=51       -> OS 4.0
      /* note: 3.1.4 is enough, but intuition.library v46 is required */

DEF    bOS4=FALSE
        
     /* default values, can be overridden by tooltypes */  
DEF  iSnapMarginWidth=10, 
        iSnapMarginHeight=10, 
        iSnapMarginPercent=3,
        bKeepMenuBar=TRUE, 
        bShowSnapArea=FALSE


DEF broker_mp=NIL:PTR TO mp, 
    broker=NIL, cxmsg=NIL, sig_broker,
    bCommodityActive=TRUE,
    cocustom=NIL, signal=-1, cxobjsignal, cosignal

DEF ie:PTR TO inputevent
DEF pubScreen=NIL:PTR TO screen



PROC main() HANDLE

    DEF ttypes=NIL,
        iCxPriority=0,
        cxfunc=NIL, task=NIL,
        intuition=NIL:PTR TO intuitionbase

    -> Check Kickstart version
    IF (KickVersion(OS_314_VERSION)=FALSE) THEN Raise(ERR_KICKSTART)
    IF KickVersion(OS_4_VERSION)  THEN bOS4:=TRUE

    
    -> Lock the public screen
    pubScreen:=LockPubScreen(NIL)
    IF pubScreen=NIL THEN Raise(ERR_NO_PUBSCREEN)


    -> open required libraries (intuition is already opened by E)
    intuition:=intuitionbase
    cxbase:=NIL
    iconbase:=NIL

    IF (intuition.libnode.version <46 ) THEN Raise(ERR_NOINTUITION)
    IF (cxbase:=OpenLibrary('commodities.library', 39))=NIL THEN Raise(ERR_NOCOMMODITY)
    IF (iconbase:=OpenLibrary('icon.library', 39))=NIL THEN Raise(ERR_NOICON)



    -> Read tooltypes
    IF (ttypes:=argArrayInit())=NIL THEN Raise(ERR_ARG_TT)

    iCxPriority:=argInt(ttypes, 'CX_PRIORITY', 0)
    IF iCxPriority > 127  THEN iCxPriority := 127
    IF iCxPriority < -128 THEN iCxPriority := -127

    -> default snapMargin as 3% of screen size
    iSnapMarginWidth:=argInt(ttypes, 'SNAP_MARGIN', -1)
    IF iSnapMarginWidth <> -1
        IF iSnapMarginWidth > 100 THEN iSnapMarginWidth :=100
        IF iSnapMarginWidth < 2   THEN iSnapMarginWidth := 2
        iSnapMarginHeight:= iSnapMarginWidth
    ELSE
        iSnapMarginWidth:= (($FFFF AND pubScreen.width)* 3)/100
        iSnapMarginHeight:= (($FFFF AND pubScreen.height) * 3)/100
    
    ENDIF

    iSnapMarginPercent:=argInt(ttypes, 'SNAP_MARGINPCT', -1)
    IF (iSnapMarginPercent > 0) AND (iSnapMarginPercent <=15)  
        iSnapMarginWidth:= (($FFFF AND pubScreen.width)* iSnapMarginPercent)/100
        iSnapMarginHeight:= (($FFFF AND pubScreen.height) * iSnapMarginPercent)/100
    ENDIF


    IF  StrCmp('YES', TrimStr(UpperStr(argString(ttypes, 'KEEP_MENUBAR', 'YES'))),3)
        bKeepMenuBar:=TRUE
    ELSE
        bKeepMenuBar:=FALSE
    ENDIF

    IF  StrCmp('YES', TrimStr(UpperStr(argString(ttypes, 'SHOW_SNAPAREA_AT_START', 'NO'))),3)
        bShowSnapArea:=TRUE
    ENDIF



    -> Create a message port for the broker
    broker_mp:=CreateMsgPort()
    IF broker_mp=NIL THEN Raise(ERR_CREATE_BROKER_PORT)
    sig_broker:=Shl(1, broker_mp.sigbit)

    -> Create the broker
    broker:=CxBroker([NB_VERSION, 0,
                   'GoSnap',   -> String to identify this broker
                   'GoSnap v0.18 by Krzysztof Donat',
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

    

    IF bShowSnapArea=TRUE THEN showSnapAreaAtStart()

    processMessages()

    EXCEPT DO


        
        IF signal<>-1 THEN FreeSignal(signal)

        IF broker THEN DeleteCxObjAll(broker)
        IF broker_mp
            WHILE cxmsg:=GetMsg(broker_mp) DO ReplyMsg(cxmsg)
            DeleteMsgPort(broker_mp)
        ENDIF


        IF ttypes       THEN argArrayDone()
        IF iconbase     THEN CloseLibrary(iconbase)
        IF cxbase       THEN CloseLibrary(cxbase)

        IF pubScreen THEN UnlockPubScreen(NIL, pubScreen)


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

    -> risk: assuming that the error message will not exceed 250 characters, better way is calculate the length (todo)
    str:=String(250)

    IF (str)

        StringF(str, 'GoSnap error (\d) - \s', excp, strError )

        IF wbmessage=NIL
            -> started from CLI - print error to CLI
            WriteF(str)
        ELSE
            -> Show a requester on Workbench screen
            EasyRequestArgs(
                NIL,[SIZEOF easystruct,0,'GoSnap',str,'Oh, no...'],0,0)
        ENDIF
        -> deallocate the string
        DisposeLink(str)
    ENDIF

ENDPROC

PROC processMessages()

    DEF  cxmsgid=0,  cxmsgtype=0, 
    sigrcvd, snapPosition=POS_NONE, done=FALSE,
    activeWindowOnScreen=NIL:PTR TO window,

    wndDownButton=NIL:PTR TO window,
    wndUpButton=NIL:PTR TO window,
    wndDownX=-1, wndDownY=-1,
    wndUpX=-1, wndUpY=-1,
    bLeftButtonIsDown=FALSE


    REPEAT

        sigrcvd:=Wait(SIGBREAKF_CTRL_C OR sig_broker OR cxobjsignal)

        -> message from the broker
        IF sigrcvd AND sig_broker 

            WHILE cxmsg:=GetMsg(broker_mp)
                cxmsgid:=CxMsgID(cxmsg)
                cxmsgtype:=CxMsgType(cxmsg)
                ReplyMsg(cxmsg)
                
                    SELECT cxmsgid
                        CASE CXCMD_DISABLE

                                ActivateCxObj(broker, FALSE)
                                bCommodityActive:=FALSE
                        
                        CASE CXCMD_ENABLE
                        
                                ActivateCxObj(broker, TRUE)
                                bCommodityActive:=TRUE
                        
                        CASE CXCMD_KILL
                            
                                done:=TRUE
                            
                    ENDSELECT
            ENDWHILE

        ENDIF

        -> CTRL-C pressed, only when running from CLI
        IF sigrcvd AND SIGBREAKF_CTRL_C 
            done:=TRUE
        ENDIF 

        -> message from the custom CxObj
        IF sigrcvd AND cxobjsignal

            IF ((ie.qualifier AND IEQUALIFIER_LEFTBUTTON) = IEQUALIFIER_LEFTBUTTON)
                IF (bLeftButtonIsDown=FALSE)

                    bLeftButtonIsDown:=TRUE

                    activeWindowOnScreen:=findActiveWindow()
                    IF activeWindowOnScreen
                            wndDownButton:=activeWindowOnScreen
                            wndDownX:=wndDownButton.leftedge
                            wndDownY:=wndDownButton.topedge

                            wndUpButton:=NIL
                    ENDIF    
                    
                ENDIF
            ELSE
                IF (bLeftButtonIsDown) 
                    
                    
                    Delay(5) -> work better on fast systems (todo: why...?)
                    bLeftButtonIsDown:=FALSE

                    activeWindowOnScreen:=findActiveWindow()
                    
                    IF (activeWindowOnScreen AND (wndDownButton=activeWindowOnScreen))
                            IF wndDownButton
                                wndUpButton:=activeWindowOnScreen
                                wndUpX:=wndUpButton.leftedge
                                wndUpY:=wndUpButton.topedge
                            
                            ENDIF
                    ENDIF
                    
                ENDIF
            ENDIF

            -> After releasing the mouse button, is the same window still active?
            IF (wndDownButton  AND (wndDownButton=wndUpButton))
                ->Delay(1)
                ->WriteF('releasing:  wndDownButton=wndUpButton\n')
                -> Did the window's position change?
                IF (wndDownX<>wndUpX) OR (wndDownY<>wndUpY)
                    ->WriteF('releasing:  wndDownX<>wndUpX\n')
                    -> Was the mouse cursor in the snapping zone?
                    snapPosition:=getSnapPosision(pubScreen.mousex, pubScreen.mousey)
                    ->WriteF('releasing:  snapPosition: \d\n', snapPosition)
                    IF (snapPosition<>POS_NONE)
                        -> Then it’s a snap!
                        ->WriteF('releasing:  SNAP!\n')
                    
                        snapWindow(wndDownButton, snapPosition)
                    ENDIF
                        
                    
                          
                ENDIF

                wndDownButton:=NIL
                wndUpButton:=NIL
                wndDownX:=-1
                wndUpX:=-1
                wndDownY:=-1
                wndUpY:=-1


            ENDIF

           
        ENDIF
    UNTIL done


ENDPROC

/* Snap the window to the specified position */
PROC snapWindow(wnd:PTR TO window, snapPosition)


    DEF newWidth, newHeight, newX, newY, iMenuBar=0, iGap=1,
        maxHeight, minHeigth, maxWidth, minWidth

    IF (bKeepMenuBar = TRUE)
         iMenuBar   := pubScreen.barheight
         iGap       := 1
    ELSE
        iMenuBar    := 0
        iGap        := 0
    ENDIF

    IF isResizableWindow(wnd)
        maxWidth:=$FFFF AND wnd.maxwidth
        minWidth:=$FFFF AND wnd.minwidth
        maxHeight:=$FFFF AND wnd.maxheight 
        minHeigth:=$FFFF AND wnd.minheight

    ELSE
        maxWidth:=$FFFF AND wnd.width
        minWidth:=$FFFF AND wnd.width
        maxHeight:=$FFFF AND wnd.height 
        minHeigth:=$FFFF AND wnd.height

    ENDIF

    SELECT snapPosition
        CASE POS_LEFT_UP

            newWidth:=pubScreen.width /2
            newHeight:=(pubScreen.height - iMenuBar) /2
            
            IF newWidth > maxWidth  THEN newWidth:=maxWidth
            IF newWidth < minWidth  THEN newWidth:=minWidth
            IF newHeight > maxHeight THEN newHeight:=maxHeight
            IF newHeight < minHeigth THEN newHeight:=minHeigth
            
            newX:=pubScreen.leftedge
            newY:=pubScreen.topedge+iMenuBar + iGap
            
        CASE POS_RIGHT_UP

            newWidth:=pubScreen.width /2
            newHeight:=(pubScreen.height - iMenuBar) /2
            
            IF newWidth > maxWidth  THEN newWidth:=maxWidth
            IF newWidth < minWidth  THEN newWidth:=minWidth
            IF newHeight > maxHeight THEN newHeight:=maxHeight
            IF newHeight < minHeigth THEN newHeight:=minHeigth
            
            newX:=pubScreen.width - newWidth
            newY:=pubScreen.topedge+iMenuBar +iGap
                        
        CASE POS_LEFT_DOWN
            
            newWidth:=pubScreen.width /2
            newHeight:=((pubScreen.height - iMenuBar) /2)-iGap

            IF newWidth > maxWidth  THEN newWidth:=maxWidth
            IF newWidth < minWidth  THEN newWidth:=minWidth
            IF newHeight > maxHeight THEN newHeight:=maxHeight
            IF newHeight < minHeigth THEN newHeight:=minHeigth
            
            newX:=pubScreen.leftedge
            newY:=pubScreen.height - newHeight
            
        CASE POS_RIGHT_DOWN

            newWidth:=pubScreen.width /2
            newHeight:=((pubScreen.height - iMenuBar) /2)-iGap

            IF newWidth > maxWidth  THEN newWidth:=maxWidth
            IF newWidth < minWidth  THEN newWidth:=minWidth
            IF newHeight > maxHeight THEN newHeight:=maxHeight
            IF newHeight < minHeigth THEN newHeight:=minHeigth
            
            newX:=pubScreen.width - newWidth 
            newY:=pubScreen.height-newHeight
            
            

        CASE POS_LEFT
            
            newWidth:=pubScreen.width /2
            newHeight:=(pubScreen.height - iMenuBar)-iGap

            IF newWidth > maxWidth  THEN newWidth:=maxWidth
            IF newWidth < minWidth  THEN newWidth:=minWidth
            IF newHeight > maxHeight THEN newHeight:=maxHeight
            IF newHeight < minHeigth THEN newHeight:=minHeigth

            newX:=pubScreen.leftedge
            newY:=((pubScreen.height-iMenuBar-newHeight)/2)+iMenuBar+iGap

        CASE POS_RIGHT

            newWidth:=pubScreen.width /2
            newHeight:=(pubScreen.height - iMenuBar)-iGap

            IF newWidth > maxWidth  THEN newWidth:=maxWidth
            IF newWidth < minWidth  THEN newWidth:=minWidth
            IF newHeight > maxHeight THEN newHeight:=maxHeight
            IF newHeight < minHeigth THEN newHeight:=minHeigth
            

            newX:=pubScreen.width-newWidth
            newY:=((pubScreen.height-iMenuBar-newHeight)/2)+iMenuBar+iGap

        CASE POS_UP

            newWidth:=pubScreen.width
            newHeight:=(pubScreen.height - iMenuBar)-iGap

            IF newWidth > maxWidth  THEN newWidth:=maxWidth
            IF newWidth < minWidth  THEN newWidth:=minWidth
            IF newHeight > maxHeight THEN newHeight:=maxHeight
            IF newHeight < minHeigth THEN newHeight:=minHeigth
            
            
            newX:=(pubScreen.width-newWidth)/2
            newY:=pubScreen.topedge+iMenuBar+iGap

        CASE POS_DOWN

            newWidth:=pubScreen.width 
            newHeight:=((pubScreen.height - iMenuBar)/2)-iGap

            IF newWidth > maxWidth  THEN newWidth:=maxWidth
            IF newWidth < minWidth  THEN newWidth:=minWidth
            IF newHeight > maxHeight THEN newHeight:=maxHeight
            IF newHeight < minHeigth THEN newHeight:=minHeigth
            
            newX:=(pubScreen.width-newWidth)/2
            newY:=pubScreen.height - newHeight
            
    ENDSELECT

    
    IF (isWindowsStillOpen(wnd))
        ChangeWindowBox( wnd, newX, newY, newWidth, newHeight )
        IF bOS4 THEN WindowToFront(wnd)
    ENDIF

ENDPROC

/* Check if the window is still open on the screen */
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

/*
    * Find the active window on the public screen
*/
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

/*
    * Check if the window is resizable
*/  
PROC isResizableWindow(wnd:PTR TO window)

    RETURN ((wnd.flags AND WFLG_SIZEGADGET ) = WFLG_SIZEGADGET ) ? TRUE : FALSE

ENDPROC


/*
    * Determine if the mouse pointer is in a snap zone
*/
PROC getSnapPosision(x, y)

    DEF screenWidth, screenHeight
    DEF screenLeft, screenTop

    screenWidth:=pubScreen.width
    screenHeight:=pubScreen.height

    screenLeft:=pubScreen.leftedge
    screenTop:=pubScreen.topedge
    
    ->WriteF('x,y: \d \d \n', x, y)

    IF (x < iSnapMarginWidth) AND (y < iSnapMarginHeight)  THEN           
        RETURN POS_LEFT_UP

    IF (x > (screenWidth-iSnapMarginWidth)) AND (y < iSnapMarginHeight) THEN               
        RETURN POS_RIGHT_UP

    IF (x < iSnapMarginWidth) AND (y > (screenHeight-iSnapMarginHeight)) THEN              
        RETURN POS_LEFT_DOWN

    IF (x > (screenWidth-iSnapMarginWidth)) AND (y > (screenHeight-iSnapMarginHeight)) THEN 
        RETURN POS_RIGHT_DOWN

    IF (x < iSnapMarginWidth) THEN                                         
        RETURN POS_LEFT
    
    IF (x > (screenWidth-iSnapMarginWidth)) THEN 
        RETURN POS_RIGHT
    
    IF (y < iSnapMarginHeight) THEN   
        RETURN POS_UP
    
    IF (y > (screenHeight-iSnapMarginHeight)) THEN  
        RETURN POS_DOWN
    
    RETURN POS_NONE    

ENDPROC 

/* Show snap areas at the start of the program */
PROC showSnapAreaAtStart()

DEF winTopLeft=NIL, winTopRight=NIL, winDownLeft=NIL, winDownRight=NIL,
    winTop=NIL, winDown=NIL, winLeft=NIL, winRight=NIL,
    x,y, width, height

    -> topLeft
    x:=0
    y:=0
    width:=iSnapMarginWidth
    height:=iSnapMarginHeight
    winTopLeft:=drawSnapArea(x, y, width, height, 1)

    x:=pubScreen.width-iSnapMarginWidth
    y:=0
    width:=iSnapMarginWidth
    height:=iSnapMarginHeight
    winTopRight:=drawSnapArea(x, y, width, height, 1)

    x:=0
    y:=pubScreen.height-iSnapMarginHeight
    width:=iSnapMarginWidth
    height:=iSnapMarginHeight
    winDownLeft:=drawSnapArea(x, y, width, height, 1)

    x:=pubScreen.width-iSnapMarginWidth
    y:=pubScreen.height-iSnapMarginHeight
    width:=iSnapMarginWidth
    height:=iSnapMarginHeight
    winDownRight:=drawSnapArea(x, y, width, height, 1)

    x:=0+iSnapMarginWidth
    y:=0
    width:=pubScreen.width - (2*iSnapMarginWidth)
    height:=iSnapMarginHeight
    winTop:=drawSnapArea(x, y, width, height, 3)
    
    x:=0+iSnapMarginWidth
    y:=pubScreen.height - iSnapMarginHeight
    width:=pubScreen.width - (2*iSnapMarginWidth)
    height:=iSnapMarginHeight
    winDown:=drawSnapArea(x, y, width, height, 3)

    x:=0
    y:=0+iSnapMarginHeight
    width:=iSnapMarginWidth
    height:=pubScreen.height-(2*iSnapMarginHeight)
    winLeft:=drawSnapArea(x, y, width, height, 3)

    x:=pubScreen.width-iSnapMarginWidth
    y:=0+iSnapMarginHeight
    width:=iSnapMarginWidth
    height:=pubScreen.height-(2*iSnapMarginHeight)
    winRight:=drawSnapArea(x, y, width, height, 3)

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

/* Draw a snap area window */
PROC drawSnapArea(x, y, width, height, color)

    DEF win=NIL:PTR TO window

    ->win := OpenW(x,y,wid,hgt,idcmp,wflgs,title,scrn,sflgs,gads,tags=NIL) 
    win := OpenW(x,y,width,height,NIL,WFLG_BORDERLESS,NIL,NIL,1,NIL,NIL)
    Box(0,0, width, height, color)


ENDPROC win

version:
CHAR '$VER: GoSnap 0.18 (08.10.2025) http://www.bitplan.pl/amiga',0

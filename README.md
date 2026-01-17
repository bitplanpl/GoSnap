# GoSnap
```
Short:        Snaps windows to screen edges
Uploader:     Krzysztof Donat (bitplan.pl gmail.com)
Author:       Krzysztof Donat (bitplan.pl gmail.com)
Type:         util/cdity
Replaces:     util/cdity/GoSnap.lha
Version:      0.20
Date:         17-01-2026
Architecture: m68k-amigaos >= 3.1.4
Distribution: Aminet

GoSnap is a program that brings to AmigaOS a window snapping feature known
from modern operating systems, allowing windows to snap to the edges 
of the screen.

GoSnap creates 8 active zones on the Workbench screen: 4 screen corners 
and 4 edges. When a window is dragged to one of these zones, 
it is automatically resized and repositioned. 
The zones work as follows:

    * 4 corners - dragging a window into a corner will resize it to 1/4 
      of the screen size and position it in that corner.
    * Left, right, and bottom edges - dragging a window to one of these 
      edges will resize it to 1/2 of the screen size and snap it 
      to the corresponding edge.
    * Top edge - dragging a window to the top edge of the screen will 
      maximize it to fill the entire screen.

GoSnap respects the minimum and maximum window sizes defined 
by the application's developer, as well as whether a window is resizable 
at all. If a window is not resizable, GoSnap will only reposition it 
without changing its size.

The program runs as a commodity and can be managed through the system 
Exchange utility, where it can be paused or disabled.

You can see GoSnap in action in the YouTube video:
https://youtu.be/hqOuVz3D1YI

Requirements:
The program requires AmigaOS version 3.1.4 or newer; AmigaOS 3.2 
is recommended.
In the system preferences (IControl), the option to allow windows 
to be dragged beyond the screen edge should be enabled.
GoSnap should also work under AmigaOS 4.1.

Installation:
Just copy GoSnap to any location and run it. 
If you want GoSnap to start automatically with Workbench, copy it 
to the WBStartup drawer.

Configuration:
GoSnap offers several Tool Type options that affect how 
the program behaves:

    * KEEP_MENUBAR=YES|NO - determines whether the top Workbench menubar 
      should be covered when snapping a window to the top of the screen, 
      or if it should always remain visible.

    * SNAP_MARGIN=10 - defines the size (in pixels) of the screen-edge 
      area where window snapping is triggered (int, range: 2-100)

    * SNAP_MARGINPCT=3 - a parameter that defines the width and height 
      of the snap area as a percentage of the screen’s width and height.
      For example, on an 800×600 screen and with the parameter set to 3, 
      the snap area near the left and right edges will be 24 pixels wide, 
      and 18 pixels high near the top and bottom edges (int, range: 1-15).
      If both parameters are defined (SNAP_MARGIN and SNAP_MARGINPCT), 
      SNAP_MARGINPCT takes priority over SNAP_MARGIN.

    * SHOW_SNAP_AREA_AT_START=YES|NO - a test feature that displays defined 
      snap zones when the program starts.

License & Donations:
GoSnap is FREEWARE, but if you find this tool useful, you are welcome 
to donate and help keep the author caffeinated:

https://www.paypal.me/krzysztofdonat

It was written in Amiga E, using the excellent E-VO compiler:
http://aminet.net/package/dev/e/evo


History:

0.20 (2026-01-17)
  - added: disable window snapping while holding SHIFT

0.19 (2025-11-28)
  - added support for ScreenNotify to monitor Workbench screen changes
    (optionally, works if the screennotify.library is present in the system)

0.18 (2025-10-08)
  - optimization fixes

0.17 (2025-07-30)
  - Fix for the non-working tooltype SHOW_SNAPAREA_AT_START
  - added icons created by EctoOne

0.16 (2025-07-01)
  - fix for window dragging detection

0.15 (2025-05-20)
  - Added ToolType parameter SNAP_MARGINPCT, defining the snap area 
    as a percentage of the screen width/height.
  - improved calculation of snapped window positions.

0.14 (2025-05-19)
  - fix for snapping non-resizable windows

0.13 (2025-05-18)
  - Initial release.

Thanks!
```	

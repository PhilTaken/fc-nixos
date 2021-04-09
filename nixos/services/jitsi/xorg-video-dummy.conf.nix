# Taken from the Jibri Debian package.

with builtins;

{ xorg, xkeyboard_config, resolution }: ''
Section "ServerFlags"
  Option "DontVTSwitch" "true"
  Option "AllowMouseOpenFail" "true"
  Option "PciForceNone" "true"
  Option "AutoEnableDevices" "false"
  Option "AutoAddDevices" "false"
EndSection

Section "Files"
  ModulePath "${xorg.xorgserver.out}/lib/xorg/modules"
  ModulePath "${xorg.xf86videodummy}/lib/xorg/modules"
  ModulePath "${xorg.xf86inputvoid}/lib/xorg/modules"
  XkbDir "${xkeyboard_config}/share/X11/xkb"
  FontPath "${xorg.fontadobe75dpi}/lib/X11/fonts/75dpi"
  FontPath "${xorg.fontadobe100dpi}/lib/X11/fonts/100dpi"
  FontPath "${xorg.fontmiscmisc}/lib/X11/fonts/misc"
  FontPath "${xorg.fontcursormisc}/lib/X11/fonts/misc"
EndSection

Section "InputDevice"
  Identifier "dummy_mouse"
  Option "CorePointer" "true"
  Driver "void"
EndSection

Section "InputDevice"
  Identifier "dummy_keyboard"
  Option "CoreKeyboard" "true"
  Driver "void"
EndSection

Section "Device"
  Identifier "dummy_videocard"
  Driver "dummy"
  Option "ConstantDPI" "true"
  #VideoRam 4096000
  #VideoRam 256000
  VideoRam 192000
EndSection

Section "Monitor"
  Identifier "dummy_monitor"
  HorizSync   5.0 - 1000.0
  VertRefresh 5.0 - 200.0
  #This can be used to get a specific DPI, but only for the default resolution:
  #DisplaySize 508 317
  #NOTE: the highest modes will not work without increasing the VideoRam
  # for the dummy video card.
  Modeline "32768x32768" 15226.50 32768 35800 39488 46208 32768 32771 32781 32953
  Modeline "32768x16384" 7516.25 32768 35544 39192 45616 16384 16387 16397 16478
  Modeline "16384x8192" 2101.93 16384 16416 24400 24432 8192 8390 8403 8602
  Modeline "8192x4096" 424.46 8192 8224 9832 9864 4096 4195 4202 4301
  Modeline "5496x1200" 199.13 5496 5528 6280 6312 1200 1228 1233 1261
  Modeline "5280x1080" 169.96 5280 5312 5952 5984 1080 1105 1110 1135
  Modeline "5280x1200" 191.40 5280 5312 6032 6064 1200 1228 1233 1261
  Modeline "5120x3200" 199.75 5120 5152 5904 5936 3200 3277 3283 3361
  Modeline "4800x1200" 64.42 4800 4832 5072 5104 1200 1229 1231 1261
  Modeline "3840x2880" 133.43 3840 3872 4376 4408 2880 2950 2955 3025
  Modeline "3840x2560" 116.93 3840 3872 4312 4344 2560 2622 2627 2689
  Modeline "3840x2048" 91.45 3840 3872 4216 4248 2048 2097 2101 2151
  Modeline "3840x1080" 100.38 3840 3848 4216 4592 1080 1081 1084 1093
  Modeline "3600x1200" 106.06 3600 3632 3984 4368 1200 1201 1204 1214
  Modeline "3288x1080" 39.76 3288 3320 3464 3496 1080 1106 1108 1135
  Modeline "2048x2048" 49.47 2048 2080 2264 2296 2048 2097 2101 2151
  Modeline "2048x1536" 80.06 2048 2104 2312 2576 1536 1537 1540 1554
  Modeline "2560x1600" 47.12 2560 2592 2768 2800 1600 1639 1642 1681
  Modeline "2560x1440" 42.12 2560 2592 2752 2784 1440 1475 1478 1513
  Modeline "1920x1440" 69.47 1920 1960 2152 2384 1440 1441 1444 1457
  Modeline "1920x1200" 26.28 1920 1952 2048 2080 1200 1229 1231 1261
  Modeline "1920x1080" 23.53 1920 1952 2040 2072 1080 1106 1108 1135
  Modeline "1680x1050" 20.08 1680 1712 1784 1816 1050 1075 1077 1103
  Modeline "1600x1200" 22.04 1600 1632 1712 1744 1200 1229 1231 1261
  Modeline "1600x900" 33.92 1600 1632 1760 1792 900 921 924 946
  Modeline "1440x900" 30.66 1440 1472 1584 1616 900 921 924 946
  ModeLine "1366x768" 72.00 1366 1414 1446 1494  768 771 777 803
  Modeline "1280x1024" 31.50 1280 1312 1424 1456 1024 1048 1052 1076
  Modeline "1280x800" 24.15 1280 1312 1400 1432 800 819 822 841
  Modeline "1280x768" 23.11 1280 1312 1392 1424 768 786 789 807
  Modeline "1360x768" 24.49 1360 1392 1480 1512 768 786 789 807
  Modeline "1024x768" 18.71 1024 1056 1120 1152 768 786 789 807
  Modeline "768x1024" 19.50 768 800 872 904 1024 1048 1052 1076


  #common resolutions for android devices (both orientations):
  Modeline "800x1280" 25.89 800 832 928 960 1280 1310 1315 1345
  Modeline "1280x800" 24.15 1280 1312 1400 1432 800 819 822 841
  Modeline "720x1280" 30.22 720 752 864 896 1280 1309 1315 1345
  Modeline "1280x720" 27.41 1280 1312 1416 1448 720 737 740 757
  Modeline "768x1024" 24.93 768 800 888 920 1024 1047 1052 1076
  Modeline "1024x768" 23.77 1024 1056 1144 1176 768 785 789 807
  Modeline "600x1024" 19.90 600 632 704 736 1024 1047 1052 1076
  Modeline "1024x600" 18.26 1024 1056 1120 1152 600 614 617 631
  Modeline "536x960" 16.74 536 568 624 656 960 982 986 1009
  Modeline "960x536" 15.23 960 992 1048 1080 536 548 551 563
  Modeline "600x800" 15.17 600 632 688 720 800 818 822 841
  Modeline "800x600" 14.50 800 832 880 912 600 614 617 631
  Modeline "480x854" 13.34 480 512 560 592 854 873 877 897
  Modeline "848x480" 12.09 848 880 920 952 480 491 493 505
  Modeline "480x800" 12.43 480 512 552 584 800 818 822 841
  Modeline "800x480" 11.46 800 832 872 904 480 491 493 505
  #resolutions for android devices (both orientations)
  #minus the status bar
  #38px status bar (and width rounded up)
  Modeline "800x1242" 25.03 800 832 920 952 1242 1271 1275 1305
  Modeline "1280x762" 22.93 1280 1312 1392 1424 762 780 783 801
  Modeline "720x1242" 29.20 720 752 856 888 1242 1271 1276 1305
  Modeline "1280x682" 25.85 1280 1312 1408 1440 682 698 701 717
  Modeline "768x986" 23.90 768 800 888 920 986 1009 1013 1036
  Modeline "1024x730" 22.50 1024 1056 1136 1168 730 747 750 767
  Modeline "600x986" 19.07 600 632 704 736 986 1009 1013 1036
  Modeline "1024x562" 17.03 1024 1056 1120 1152 562 575 578 591
  Modeline "536x922" 16.01 536 568 624 656 922 943 947 969
  Modeline "960x498" 14.09 960 992 1040 1072 498 509 511 523
  Modeline "600x762" 14.39 600 632 680 712 762 779 783 801
  Modeline "800x562" 13.52 800 832 880 912 562 575 578 591
  Modeline "480x810" 12.59 480 512 552 584 810 828 832 851
  Modeline "848x442" 11.09 848 880 920 952 442 452 454 465
  Modeline "480x762" 11.79 480 512 552 584 762 779 783 801
EndSection

Section "Screen"
  Identifier "dummy_screen"
  Device "dummy_videocard"
  Monitor "dummy_monitor"
  DefaultDepth 24
  SubSection "Display"
    Viewport 0 0
    Depth 24
    #Modes "32768x32768" "32768x16384" "16384x8192" "8192x4096" "5120x3200" "3840x2880" "3840x2560" "3840x2048" "2048x2048" "2560x1600" "1920x1440" "1920x1200" "1920x1080" "1600x1200" "1680x1050" "1600x900" "1400x1050" "1440x900" "1280x1024" "1366x768" "1280x800" "1024x768" "1024x600" "800x600" "320x200"
    Modes "5120x3200" "3840x2880" "3840x2560" "3840x2048" "2048x2048" "2560x1600" "1920x1440" "1920x1200" "1920x1080" "1600x1200" "1680x1050" "1600x900" "1400x1050" "1440x900" "1280x1024" "1366x768" "1280x800" "1024x768" "1024x600" "800x600" "320x200"
    Virtual ${toString resolution.width} ${toString resolution.height}
  EndSubSection
EndSection

Section "ServerLayout"
  Identifier   "dummy_layout"
  Screen       "dummy_screen"
  InputDevice  "dummy_mouse"
  InputDevice  "dummy_keyboard"
EndSection
''
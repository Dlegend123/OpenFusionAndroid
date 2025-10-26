# Run OpenFusion(Offline) on Android

# Prerequisites
- Download the latest OpenfusionLauncher(Windows Portable) on PC.  https://github.com/OpenFusionProject/OpenFusionLauncher/releases
- Download the latest Openfusion Server(Windows Academy/Original) on PC. https://github.com/OpenFusionProject/OpenFusion/releases
- Download the OpenFusion.ahk file repo or copy its contents and create a new OpenFusion.ahk file. 
- Download and install AutoHotKey on PC. https://www.autohotkey.com/
- Download and install Winlator and/Gamehub on the Android device. https://github.com/Dlegend123/OpenFusionAndroid/blob/master/OpenFusion.ahk

1. Create an OpenFusion folder.
2. Copy the extracted OpenFusionLauncher-main folder to the OpenFusion folder.
3. Download offline cache
- Click the gear button at the bottom left
- Click on the Game Builds tab.
- Click the download button in the offline cache column for the specific build.
- Click the blue button beside the download button.
- In the new window copy the name of the current folder.
- Open the OpenFusion.ahk file in a text editor and replace the `VERSION_UUID`'s value, "6543a2bb-d154-4087-b9ee-3c8aa778580a", with the name of the folder. Do not remove the quotation marks.
- Copy the parent offline_cache folder to the OpenFusionLauncher-main folder you extracted
4. Rename OpenFusionLauncher-main to OpenFusionLauncher.
5. Create an OpenFusionServer folder in the OpenFusion folder and copy the extracted contents of Openfusion Server(Windows Academy/Original) to it
7. Open AutoHotKey Dash.
8. Click on Compile.
9. Click the `Browse` button at the `Source(script file)` field and select the OpenFusion.ahk file.
10. Click the `Browse` button at the `Destination(.exe file)` field and go to the OpenFusion folder.
11. Enter a name for the exe file then click `Save`.
12. Click the `Convert` button at the `Convert to executable` label.
13. Move the OpenFusion folder to your Android Device.

## OpenFusion directory
![alt text](https://github.com/Dlegend123/OpenFusionAndroid/blob/master/OpenFusion.png)

## OpenFusion/OpenFusionLauncher directory
![alt text](https://github.com/Dlegend123/OpenFusionAndroid/blob/master/OpenFusionLauncher.png)

## OpenFusion/OpenFusionServer directory
![alt text](https://github.com/Dlegend123/OpenFusionAndroid/blob/master/OpenFusionServer.png)

## Winlator

## Gamehub
- Import the OpenFusion.exe file in Gamehub.
- Use proton10.0-arm64x-2 as the `Compatibility Layer`.
- Use Performance as the `Translation Params`.
- For the `DXVK Version` you can use dxvk-v2.6.2-1-async.

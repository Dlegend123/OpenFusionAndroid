# Run OpenFusion(Offline) on Android

# Prerequisites
- Download the latest OpenfusionLauncher(Windows Portable) on PC.  https://github.com/OpenFusionProject/OpenFusionLauncher/releases
- Download the latest Openfusion Server(Windows Academy/Original) on PC. https://github.com/OpenFusionProject/OpenFusion/releases
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
6. Copy the config.ini file from the OpenFusion Server and paste it into the OpenFusion folder. Add the following lines to the end of the file:
	```
	[launcher]
	# full path to the OpenFusionServer folder
	server_dir=OpenFusionServer

	# full path to the OpenFusionLauncher folder
	launcher_dir=OpenFusionLauncher

	# path to the offline_cache directory
	cache_dir=OpenFusionLauncher\offline_cache

	# UUID folder name inside offline_cache
	version_uuid=6543a2bb-d154-4087-b9ee-3c8aa778580a

	# optional: username for automatic login (if supported)
	#username=dummy

	# optional: authentication token for automatic login
	#token=dummy

	# optional: custom window dimensions (ffrunner uses defaults if omitted)
	width=2560
	height=1440

	# optional: custom log file (ffrunner uses internal default if omitted)
	log_file=ffrunner_output.txt
	```
7. Move the OpenFusion folder to your Android Device.

## OpenFusion directory
![alt text](https://github.com/Dlegend123/OpenFusionAndroid/blob/master/OpenFusion.png)

## OpenFusion/OpenFusionLauncher directory
![alt text](https://github.com/Dlegend123/OpenFusionAndroid/blob/master/OpenFusionLauncher.png)

## OpenFusion/OpenFusionServer directory
![alt text](https://github.com/Dlegend123/OpenFusionAndroid/blob/master/OpenFusionServer.png)

## Winlator

## Gamehub
- Import the OpenFusion.exe file in Gamehub.
- Use wine10.6-arm64x-2 as the `Compatibility Layer`.
- Use Extreme as the `Translation Params`.
- For the `DXVK Version` you can use dxvk-1.10.3

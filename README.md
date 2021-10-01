<p align="center"><img src="./DiaBLE/Assets.xcassets/AppIcon.appiconset/Icon.png" width="25%" /></p>


The project started as a single script for the iPad Swift Playgrounds to test the workings of the several troublesome BLE devices I bought, mainly the **Bubble** and the **MiaoMiao**. It was then quickly converted to an app when the **Libre 2** came out at last by using a standard Xcode template: it should compile fine without external dependencies just after changing the _Bundle Identifier_ in the _General_ panel and the _Team_ in the _Signing and Capabilities_ tab of Xcode -- Spike users know already very well what that means... ;-)

I am targeting only the latest betas of Xcode and iOS.

***Disclaimer***: the decrypting keys I am publishing are not related to user accounts and can be dumped from the sensor memory by using DiaBLE itself. The online servers I am using probably are tracking your personal data but all the traffic sent/received by DiaBLE is clearly shown in its logs. The reversed code I am pasting has been retrieved from other GitHub repos or reproduced simply by using open-source tools like `jadx-gui`.

---
Credits: [@bubbledevteam](https://github.com/bubbledevteam?tab=repositories), [@captainbeeheart](https://github.com/captainbeeheart?tab=repositories), [@cryptax](https://github.com/cryptax?tab=repositories), [@dabear](https://github.com/dabear?tab=repositories), [@ivalkou](https://github.com/ivalkou?tab=repositories), [@keencave](https://github.com/keencave), [LibreMonitor](https://github.com/UPetersen/LibreMonitor/tree/Swift4), [Loop](https://github.com/LoopKit/Loop), [Marek Macner](https://github.com/MarekM60), [Nightguard]( https://github.com/nightscout/nightguard), [@travisgoodspeed](https://github.com/travisgoodspeed?tab=repositories), [WoofWoof](https://github.com/gshaviv/ninety-two), [xDrip+](https://github.com/NightscoutFoundation/xDrip), [xDrip4iO5](https://github.com/JohanDegraeve/xdripswift).
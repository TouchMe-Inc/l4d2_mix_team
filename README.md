# About mix_team
Plugin adds voting for mixing teams. The mix_team plugin itself does not implement any mixing of players, but provides an API. 

## Preview
![image](https://github.com/user-attachments/assets/80bd8f84-c609-405a-af4c-6534ade21c0a)

## Commands
* `!mix` - Show menu with mixtypes.
* `!fmix` - Show menu with mixtypes. Run without vote (Admin only with flag BAN).

## Available mix types:
* `random` - plugin [mt_random](/addons/sourcemod/scripting/mt_random.sp) - Shuffle players with random order.
* `capitan` - plugin [mt_capitan](/addons/sourcemod/scripting/mt_capitan.sp) - Mix with captains.
* (not work) `exp` - plugin [mt_experience](/addons/sourcemod/scripting/mt_experience.sp) - Mix based on steam stats. 

## Require
* Colors
* [NativeVotesRework](https://github.com/TouchMe-Inc/l4d2_nativevotes_rework)
* (Optional. Only for [mt_experience](/addons/sourcemod/scripting/mt_experience.sp)) [SteamWorks](https://github.com/hexa-core-eu/SteamWorks) 

## Support
* [Left4DHooks](https://github.com/SilvDev/Left4DHooks)

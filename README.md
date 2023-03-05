# About mix_team
Plugin adds voting for mixing teams

## Commands
`!mix <type>` - start mix <type>.

## How to add mix?
You must write and compile a plugin that implements all methods:
```
#include <sourcemod>
#include <mix_team>

public void OnAllPluginsLoaded() {
	AddMixType("supermix", 4); // <-- add mix type. Run: "!mix supermix"
}

public void GetVoteTitle(int iClient, char[] sTitle) {
	Format(sTitle, VOTE_TITLE_SIZE, "%T", "My vote title!"); // <-- Voting header
}

public void GetVoteMessage(int iClient, char[] sMsg) {
	Format(sMsg, VOTE_MSG_SIZE, "My vote successful!"); // <-- Message if voting is successful
}

public void OnMixStart() // <-- Point of entry
{
	CallEndMix(); // <-- Exit point
}
```

## Require
[NativeVotes](https://github.com/sapphonie/sourcemod-nativevotes-updated)

## Support
[ReadyUp](https://github.com/SirPlease/L4D2-Competitive-Rework/blob/master/addons/sourcemod/scripting/readyup.sp)

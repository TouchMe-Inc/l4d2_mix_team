# About mix_team
Plugin adds voting for mixing teams. The mix_team plugin itself does not implement any mixing of players, but provides an API. 

Several prepared author's mix types are available: mt_capitan and mt_random.

## Commands
`!mix <type>` - start mix <type>.

## How to create mix type?
You must write and compile a plugin that implements all methods:
```
#include <sourcemod>
#include <mix_team>

public void OnAllPluginsLoaded() {
	AddMixType("supermix", 4, 60); // <-- add mix type with timeout 60sec (can be interrupted). Run: "!mix supermix"
}

public void GetVoteDisplayMessage(int iClient, char[] sTitle) {
	Format(sTitle, DISPLAY_MSG_SIZE, "My vote title!"); // <-- Voting header
}

public void GetVoteEndMessage(int iClient, char[] sMsg) {
	Format(sMsg, VOTEEND_MSG_SIZE, "Vote done!"); // <-- Message if voting is successful
}

public void OnMixInProgress() // <-- Point of entry
{
	// Payload
	...
	...
	CallEndMix(); // <-- Exit point
}
```

## Require
[NativeVotes](https://github.com/sapphonie/sourcemod-nativevotes-updated)

## Support
[ReadyUp](https://github.com/SirPlease/L4D2-Competitive-Rework/blob/master/addons/sourcemod/scripting/readyup.sp)

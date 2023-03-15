# About mix_team
Plugin adds voting for mixing teams. The mix_team plugin itself does not implement any mixing of players, but provides an API. 

Several prepared author's mix types are available: mt_capitan and mt_random.

## Commands
`!mix <type>` - start mix <type>.

`!unmix` or `!cancelmix` - abort the mix.

## How to create mix type?
You must write and compile a plugin that implements all methods:
```pawn
#include <sourcemod>
#include <mix_team>

public void OnAllPluginsLoaded()
{
	// add mix type with timeout 60sec (can be interrupted). Run: "!mix supermix"
	AddMixType("supermix", 4, 60);
}

// MANDATORY set the name of the vote
public void GetVoteDisplayMessage(int iClient, char[] sTitle) { // Required!!!
	Format(sTitle, DISPLAY_MSG_SIZE, "My vote title!");
}

// MANDATORY set a message in case of success
public void GetVoteEndMessage(int iClient, char[] sMsg) { // Required!!!
	Format(sMsg, VOTEEND_MSG_SIZE, "Vote done!");
}

public void OnMixInProgress() // Required!!! Point of entry
{
	// Payload
	
	...
	CallEndMix(); // Required!!! Exit point
}
```

## Require
[NativeVotes](https://github.com/sapphonie/sourcemod-nativevotes-updated)

## Support
[ReadyUp](https://github.com/SirPlease/L4D2-Competitive-Rework/blob/master/addons/sourcemod/scripting/readyup.sp)

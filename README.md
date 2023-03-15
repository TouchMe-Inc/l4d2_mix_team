# About mix_team
Plugin adds voting for mixing teams. The mix_team plugin itself does not implement any mixing of players, but provides an API. 

Several prepared author's mix types are available: mt_capitan and mt_random.

## Commands
`!mix <type>` - start mix <type>.

## TODO
- [ ] Interrupting a mix with a chat command.

## How to add mix type?
You must write and compile a plugin that implements all methods:
```
#include <sourcemod>
#include <mix_team>

public void OnAllPluginsLoaded() {
	AddMixType("supermix", 4); // <-- add mix type. Run: "!mix supermix"
}

public void GetVoteTitle(int iClient, char[] sTitle) {
	Format(sTitle, VOTE_TITLE_SIZE, "My vote title!"); // <-- Voting header
}

public void GetVoteMessage(int iClient, char[] sMsg) {
	Format(sMsg, VOTE_MSG_SIZE, "Vote done!"); // <-- Message if voting is successful
}

public void OnMixStart() { // <-- Point of entry
	CallEndMix(); // <-- Exit point
}
```

## Require
[NativeVotes](https://github.com/sapphonie/sourcemod-nativevotes-updated)

## Support
[ReadyUp](https://github.com/SirPlease/L4D2-Competitive-Rework/blob/master/addons/sourcemod/scripting/readyup.sp)

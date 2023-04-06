#include <sourcemod>
#include <mix_team>

public void OnAllPluginsLoaded()
{
	// Add mix type with minimum number of players 4 and timeout 60sec (can be interrupted). 
	// Run: "!mix supermix"
	AddMixType("supermix", 1, 60);
}

// MANDATORY set the name of the vote
public void GetVoteDisplayMessage(int iClient, char[] sTitle) { // Required!!!
	Format(sTitle, DISPLAY_MSG_SIZE, "My vote title!");
}

// MANDATORY set a message in case of success
public void GetVoteEndMessage(int iClient, char[] sMsg) { // Required!!!
	Format(sMsg, VOTEEND_MSG_SIZE, "Vote done!");
}

public Action OnMixInProgress() // Required!!! Point of entry
{
    CallEndMix();
}

public Action Timer_EndMix()
{
	CallEndMix(); // Required!!! Exit point
	return Plugin_Stop;
}
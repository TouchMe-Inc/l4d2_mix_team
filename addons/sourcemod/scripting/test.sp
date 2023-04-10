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

public Action OnMixInProgress()
{
	CreateTimer(1.0, Timer_NextStep);

	// If the mix goes beyond the life cycle of the function, then you need to return Plugin_Handled
	return Plugin_Handled; 
}

public Action Timer_NextStep(Handle Timer)
{
	// Payload
	if (1)
	{
		CallCancelMix(); // Required if returned Plugin_Handled in OnMixInProgress();
		return Plugin_Stop;
	}

	CreateTimer(1.0, Timer_NextStep);

	return Plugin_Stop;
}


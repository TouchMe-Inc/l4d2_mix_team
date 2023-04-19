#pragma semicolon               1
#pragma newdecls                required

#include <sourcemod>
#include <mix_team>


public Plugin myinfo = { 
	name = "MixTeamRandom",
	author = "TouchMe",
	description = "Adds random mix",
	version = "build_0002",
	url = "https://github.com/TouchMe-Inc/l4d2_mix_team"
};


#define TRANSLATIONS            "mt_random.phrases"

#define MIN_PLAYERS             4


/**
 * Loads dictionary files. On failure, stops the plugin execution.
 */
void InitTranslations()
{
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "translations/" ... TRANSLATIONS ... ".txt");

	if (FileExists(sPath)) {
		LoadTranslations(TRANSLATIONS);
	} else {
		SetFailState("Path %s not found", sPath);
	}
}

/**
 * Called when the plugin is fully initialized and all known external references are resolved.
 */
public void OnPluginStart() {
	InitTranslations();
}

public void OnAllPluginsLoaded() {
	AddMix("random", MIN_PLAYERS, 0);
}

public void GetVoteDisplayMessage(int iClient, char[] sTitle) {
	Format(sTitle, DISPLAY_MSG_SIZE, "%T", "VOTE_DISPLAY_MSG", iClient);
}

public void GetVoteEndMessage(int iClient, char[] sMsg) {
	Format(sMsg, VOTEEND_MSG_SIZE, "%T", "VOTE_END_MSG", iClient);
}

/**
 * Starting the mix.
 */
public Action OnMixInProgress()
{
	Handle hPlayers = CreateArray();

	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (!IsClientInGame(iClient) || IsFakeClient(iClient) || !IsMixMember(iClient)) {
			continue;
		}

		PushArrayCell(hPlayers, iClient);
	}
	
	for (int iPlayers, iIndex, iClient;;)
	{
		iPlayers = GetArraySize(hPlayers);

		if (!iPlayers) {
			break;
		}

		iIndex = GetRandomInt(0, iPlayers - 1);
		iClient = GetArrayCell(hPlayers, iIndex);

		SetClientTeam(iClient, iPlayers % 2 == 0 ? TEAM_INFECTED : TEAM_SURVIVOR);
		RemoveFromArray(hPlayers, iIndex);
	}

	return Plugin_Continue;
}

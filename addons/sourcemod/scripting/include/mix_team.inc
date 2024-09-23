/*
	SourcePawn is Copyright (C) 2006-2008 AlliedModders LLC.  All rights reserved.
	SourceMod is Copyright (C) 2006-2008 AlliedModders LLC.  All rights reserved.
	Pawn and SMALL are Copyright (C) 1997-2008 ITB CompuPhase.
	Source is Copyright (C) Valve Corporation.
	All trademarks are property of their respective owners.

	This program is free software: you can redistribute it and/or modify it
	under the terms of the GNU General Public License as published by the
	Free Software Foundation, either version 3 of the License, or (at your
	option) any later version.

	This program is distributed in the hope that it will be useful, but
	WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
	General Public License for more details.

	You should have received a copy of the GNU General Public License along
	with this program.  If not, see <http://www.gnu.org/licenses/>.
*/
#if defined  _mix_team_included_
 #endinput
#endif
#define _mix_team_included_


enum MixState
{
	MixState_None = 0,
	MixState_Voting,
	MixState_InProgress
}


/**
 * @brief Forced end of the mix.
 * @remarks Use if Plugin_Handled is returned in OnMixInProgress.
 **/
native void Call_AbortMix();

/**
 * @brief End of the mix.
 * @remarks Use if Plugin_Handled is returned in OnMixInProgress.
 **/
native void Call_FinishMix();

/**
 * @brief Adds a mix to the voting list.
 *
 * @param iMinPlayers   Minimum number of players to mix.
 * @param iAbortDelay   Mix Interrupt Delay Time (!unmix).
 *
 * @return              MixList Index if success, otherwise throw error.
 **/
native int AddMix(int iMinPlayers, int iAbortDelay);

/**
 * @brief Returns the status of the mix.
 *
 * @return              MixState_*.
 **/
native MixState GetMixState();

/**
 * @brief Returns current Mix Index
 * @remarks The mix type is equal to the index of the element in the MixList
 *
 * @return              MixList Index or INVALID_INDEX.
 **/
native int GetMixIndex();

/**
 * @brief Returns whether the player is a member of the mix
 *
 * @param iClient       Client ID
 *
 * @return              true or false
 **/
native bool IsMixMember(int iClient);

/**
 * @brief Returns the team the player was on after voting for the mix
 *
 * @param iClient       Client ID
 *
 * @return              Returns the player's last command before mixing
 **/
native int GetLastTeam(int iClient);

/**
 * @brief Sets the player's team
 *
 * @param iClient       Client ID.
 * @param iTeam         Client team.
 *
 * @return              true if success, otherwise false.
 **/
native bool SetClientTeam(int iClient, int iTeam);


/**
 *
 */
forward Action OnDrawMenuName(int iMixIndex, int iClient, char[] sName, int iLength);

/**
 *
 */
forward Action OnDrawVoteTitle(int iMixIndex, int iClient, char[] sTitle, int iLength);

/**
 *
 */
forward Action OnChangeMixState(int iMixIndex, MixState eOldState, MixState eNewState, bool bIsFail);


public SharedPlugin __pl_mix_team =
{
	name = "mix_team",
	file = "mix_team.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_mix_team_SetNTVOptional()
{
	MarkNativeAsOptional("Call_AbortMix");
	MarkNativeAsOptional("Call_FinishMix");
	MarkNativeAsOptional("AddMix");
	MarkNativeAsOptional("GetMixState");
	MarkNativeAsOptional("GetMixIndex");
	MarkNativeAsOptional("IsMixMember");
	MarkNativeAsOptional("GetLastTeam");
	MarkNativeAsOptional("SetClientTeam");
}
#endif

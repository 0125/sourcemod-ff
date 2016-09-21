#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <l4d_myStocks>

#pragma newdecls required
#pragma semicolon 1

public Plugin myinfo = {
	name 			= "Reverse FF",
	author 			= "RB",
	description 	= "Reverses Friendly Fire",
	version 		= "1.0",
	url 			= "http://www.sourcemod.net/"
};

static	Handle	reverse_ff_enable = null;					//Cvar
static	Handle	FFTimer[MAXPLAYERS+1]; 						//Used to be able to disable the FF timer when they do more FF
static	bool	FFActive[MAXPLAYERS+1]; 					//Stores whether players are in a state of friendly firing teammates
static	int		DamageCache[MAXPLAYERS+1][MAXPLAYERS+1]; 	//Used to temporarily store Friendly Fire Damage between teammates
static	int		immuneStatus[MAXPLAYERS+1]; 				//Used to store immune status while & after survivor is under attack from SI
static	int		carryStatus[MAXPLAYERS+1]; 					//Used to store if survivor is being carried by charger
static	int		pummelStatus[MAXPLAYERS+1]; 				//Used to store if survivor is being pumelled by charger
static	int		debugMode = 1;								//Used to toggle debug logging
static	char	sGame[256];									//Game title

public void OnPluginStart() {
	GetGameFolderName(sGame, sizeof(sGame));
	
	reverse_ff_enable = CreateConVar("reverse_ff_enable", "1", "Enable reversed friendy fire");
	AutoExecConfig(true, "reverse_ff");
	
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i))
			SDKHook(i, SDKHook_OnTakeDamage, OnTakeDamage);
	
	if (StrEqual(sGame, "left4dead", false) || StrEqual(sGame, "left4dead2", false))
	{
		HookEvent("player_bot_replace", Event_player_bot_replace);
		HookEvent("bot_player_replace", Event_bot_player_replace);
		
		HookEvent("tongue_grab", Event_immunityStart);
		HookEvent("tongue_release", Event_immunityEnd);
		
		HookEvent("lunge_pounce", Event_immunityStart);
		HookEvent("pounce_end", Event_immunityEnd);
	}
	if (StrEqual(sGame, "left4dead2", false))
	{
		HookEvent("jockey_ride", Event_immunityStart);
		HookEvent("jockey_ride_end", Event_immunityEnd);
		
		HookEvent("charger_carry_start", Event_charger_carry_start);
		HookEvent("charger_carry_end", Event_charger_carry_end);
		
		HookEvent("charger_pummel_start", Event_charger_pummel_start);
		HookEvent("charger_pummel_end", Event_charger_pummel_end);
	}
}

public void OnClientPostAdminCheck(int client) {
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public void OnClientDisconnect(int client) {
	SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

/*
	OnTakeDamage()
		Plugin_Continue; = apply damage as normal
		Plugin_Handled; = do not apply damage
*/
public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3]) {
	if (!GetConVarBool(reverse_ff_enable) || !IsValidClient(attacker) || !IsValidClient(victim))
		return Plugin_Continue;
	
	if (attacker == victim || IsFakeClient(attacker) || !damage || GetClientTeam(victim) != GetClientTeam(attacker) || IsPlayerIncapped(victim))
		return Plugin_Continue;
	
	if (immuneStatus[victim] == 1 || IsPlayerIncapped(attacker))
		return Plugin_Handled;
	
	if (IsFakeClient(victim))
		return Plugin_Continue;
	
	char attackerWeapon[64];
	GetClientWeapon(attacker, attackerWeapon, sizeof(attackerWeapon));
	
	int victimDmg = RoundToNearest(damage);
	int victimDmgRemaining = victimDmg;
	int attackerHealth = GetClientHealth(attacker);
	int attackerTempHealth = GetTempHealth(attacker);
	
	// vars for LogDebug
	int victimHealth = GetClientHealth(victim);
	int victimTempHealth = GetTempHealth(victim);
	char attackerName[128];
	GetClientName(attacker, attackerName, sizeof(attackerName));
	char victimName[128];
	GetClientName(victim, victimName, sizeof(victimName));
	
	// damage inflicted indirectly for example pipebomb or propanetank explosion
	if (StrEqual(sGame, "left4dead", false) && !IsValidClient(inflictor)) // L4D2 melee weapons have random high non-client inflictor values
		return Plugin_Continue;
	else if (StrEqual(sGame, "left4dead2", false) && !StrEqual(attackerWeapon, "weapon_grenade_launcher") && weapon == -1) // L4D1 always has -1 weapon
		return Plugin_Continue;
	
	// Punish the attacker
	if( IsPlayerAlive(attacker) && IsClientInGame(attacker) )
	{
		// PrintToChatAll("'%s' (%d health & %d temphealth) attacked '%s' (%d health & %d temphealth) for %d damage", attackerName, attackerHealth, attackerTempHealth, victimName, victimHealth, victimTempHealth, victimDmg);
		LogDebug("'%s' (%d health & %d temphealth) attacked '%s' (%d health & %d temphealth) for %d damage", attackerName, attackerHealth, attackerTempHealth, victimName, victimHealth, victimTempHealth, victimDmg);
		
		if (attackerHealth - victimDmgRemaining >= 1)
		{
			LogDebug("DEBUG 100 - victimDmgRemaining: %d", victimDmgRemaining);
			int debugVar = attackerHealth - victimDmgRemaining;
			LogDebug("DEBUG 100 - Set %s's health to %d", attackerName, debugVar);
			
			SetEntityHealth(attacker, attackerHealth - victimDmgRemaining);
			victimDmgRemaining -= victimDmgRemaining;
			
			LogDebug("DEBUG 100 - victimDmgRemaining: %d", victimDmgRemaining);
		}
		else if (attackerHealth - victimDmgRemaining < 1)
		{
			LogDebug("DEBUG 101 - victimDmgRemaining: %d", victimDmgRemaining);
			
			SetEntityHealth(attacker, 1);
			victimDmgRemaining -= attackerHealth - 1;
			
			LogDebug("DEBUG 101 - Set %s's health to 1", attackerName);
			LogDebug("DEBUG 101 - victimDmgRemaining: %d", victimDmgRemaining);
		}
		
		if (attackerTempHealth != 0 && victimDmgRemaining >= 1)
		{
			if (attackerTempHealth - victimDmgRemaining >= 1)
			{
				LogDebug("DEBUG 102 - victimDmgRemaining: %d", victimDmgRemaining);
				int debugVar = attackerTempHealth - victimDmgRemaining;
				LogDebug("DEBUG 102 - Set %s's temphealth to %d", attackerName, debugVar);
				
				SetTempHealth(attacker, attackerTempHealth - victimDmgRemaining);
				victimDmgRemaining -= victimDmgRemaining;
				
				LogDebug("DEBUG 102 - victimDmgRemaining: %d", victimDmgRemaining);
			}
			else if (attackerTempHealth - victimDmgRemaining < 1)
			{
				LogDebug("DEBUG 103 - victimDmgRemaining: %d", victimDmgRemaining);
				
				SetTempHealth(attacker, 0);
				victimDmgRemaining -= attackerTempHealth;
				
				LogDebug("DEBUG 103 - Set %s's temphealth to 0", attackerName);
				LogDebug("DEBUG 103 - victimDmgRemaining: %d", victimDmgRemaining);
			}
		}
		
		if (victimDmgRemaining >= 1)
		{
			LogDebug("DEBUG 104 - victimDmgRemaining: %d", victimDmgRemaining);
			
			IncapPlayer(attacker);
			victimDmgRemaining -= 1;
			
			LogDebug("DEBUG 104 - Incapped %s", attackerName);
			LogDebug("DEBUG 104 - victimDmgRemaining: %d", victimDmgRemaining);
		}
		
		if (victimDmgRemaining >= 1 && IsPlayerIncapped(attacker))
		{
			LogDebug("DEBUG 105 - victimDmgRemaining: %d", victimDmgRemaining);
			int debugVar = 300 - victimDmgRemaining;
			LogDebug("DEBUG 105 - Set %s's health to %d", attackerName, debugVar);
			
			SetEntityHealth(attacker, 300 - victimDmgRemaining);
			victimDmgRemaining -= victimDmgRemaining;
			
			LogDebug("DEBUG 105 - victimDmgRemaining: %d", victimDmgRemaining);
		}
	}
	
	// Announce damage
	if (FFActive[attacker])  //If the player is already friendly firing teammates, resets the announce timer and adds to the damage
	{
		Handle pack;
		DamageCache[attacker][victim] += victimDmg;
		KillTimer(FFTimer[attacker]);
		FFTimer[attacker] = CreateDataTimer(1.0, AnnounceFF, pack);
		WritePackCell(pack,attacker);
	}
	else //If it's the first friendly fire by that player, it will start the announce timer and store the damage done.
	{
		DamageCache[attacker][victim] = victimDmg;
		Handle pack;
		FFActive[attacker] = true;
		FFTimer[attacker] = CreateDataTimer(1.0, AnnounceFF, pack);
		WritePackCell(pack,attacker);
		for (int i = 1; i < 19; i++)
		{
			if (i != attacker && i != victim)
			{
				DamageCache[attacker][i] = 0;
			}
		}
	}
	
	return Plugin_Handled;
}

public Action AnnounceFF(Handle timer, Handle pack) { //Called if the attacker did not friendly fire recently, and announces all FF they did
	char victim[128];
	char attacker[128];
	ResetPack(pack);
	int attackerc = ReadPackCell(pack);
	FFActive[attackerc] = false;
	if (IsClientInGame(attackerc) && IsClientConnected(attackerc) && !IsFakeClient(attackerc))
		GetClientName(attackerc, attacker, sizeof(attacker));
	else
		attacker = "Disconnected Player";
	
	for (int i = 1; i < MaxClients; i++)
	{
		if (DamageCache[attackerc][i] != 0)
		{
			if (IsClientInGame(i) && IsClientConnected(i))
			{
				GetClientName(i, victim, sizeof(victim));
				
				PrintToChatAll("Reversed %d damage %s did to %s",DamageCache[attackerc][i],attacker,victim);
					
				DamageCache[attackerc][i] = 0;
			}
		}
	}
}

public Action Event_player_bot_replace(Handle event, const char[] name, bool dontBroadcast) {
	int playerId = GetClientOfUserId(GetEventInt(event, "player"));
	
	if (StrEqual(sGame, "left4dead", false) && L4D_IsSurvivorAffectedBySI(playerId))
		immuneStatus[playerId] = 1;
	else if (StrEqual(sGame, "left4dead2", false) && L4D2_IsSurvivorAffectedBySI(playerId))
	{
		immuneStatus[playerId] = 1;
		
		if (GetEntPropEnt(playerId, Prop_Send, "m_carryAttacker") > 0)
			carryStatus[playerId] = 1;
		if (GetEntPropEnt(playerId, Prop_Send, "m_pummelAttacker") > 0)
			pummelStatus[playerId] = 1;
	}
}

public Action Event_bot_player_replace(Handle event, const char[] name, bool dontBroadcast) {
	int playerId = GetClientOfUserId(GetEventInt(event, "player"));
	
	if (StrEqual(sGame, "left4dead", false) && L4D_IsSurvivorAffectedBySI(playerId))
		immuneStatus[playerId] = 0;
	else if (StrEqual(sGame, "left4dead2", false) && L4D2_IsSurvivorAffectedBySI(playerId))
	{
		immuneStatus[playerId] = 0;
		carryStatus[playerId] = 0;
		pummelStatus[playerId] = 0;
	}
}

public Action Event_immunityStart(Handle event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(GetEventInt(event, "victim"));
	if (!IsSurvivor(client))
		return;

	// PrintToChatAll("Event_immunityStart: immuneStatus 1");
	immuneStatus[client] = 1;
}

public Action Event_immunityEnd(Handle event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(GetEventInt(event, "victim"));
	if (!IsSurvivor(client))
		return;
	
	// PrintToChatAll("Event_immunityEnd: starting Timer_immunityEnd");
	CreateTimer(3.0, Timer_immunityEnd, client);
}

public Action Event_charger_carry_start(Handle event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(GetEventInt(event, "victim"));
	if (!IsSurvivor(client))
		return;
	
	// PrintToChatAll("Event_charger_carry_start");
	carryStatus[client] = 1;
	immuneStatus[client] = 1;
}

public Action Event_charger_carry_end(Handle event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(GetEventInt(event, "victim"));
	if (!IsSurvivor(client))
		return;
	
	// PrintToChatAll("Event_charger_carry_end: starting Timer_immunityEnd");
	carryStatus[client] = 0;
	CreateTimer(3.0, Timer_immunityEnd, client);
}

public Action Event_charger_pummel_start(Handle event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(GetEventInt(event, "victim"));
	if (!IsSurvivor(client))
		return;
	
	// PrintToChatAll("Event_charger_pummel_start");
	pummelStatus[client] = 1;
	immuneStatus[client] = 1;
}

public Action Event_charger_pummel_end(Handle event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(GetEventInt(event, "victim"));
	if (!IsSurvivor(client))
		return;
	
	// PrintToChatAll("Event_charger_pummel_end: starting Timer_immunityEnd");
	pummelStatus[client] = 0;
	CreateTimer(3.0, Timer_immunityEnd, client);
}

public Action Timer_immunityEnd(Handle timer, any client) {
	if (carryStatus[client] == 1 || pummelStatus[client] == 1) // do not remove immunity if victim is being carried or pummeled by charger
	{
		// PrintToChatAll("Timer_immunityEnd: survivor is being pummeled or carried");
		return;
	}
	
	// PrintToChatAll("Timer_immunityEnd: immuneStatus 0!");
	immuneStatus[client] = 0;
}

stock void LogDebug(const char[] format, any:...) {
	if (!debugMode)
		return;
	char buffer[512];
	VFormat(buffer, sizeof(buffer), format, 2);
	Handle file;
	char FileName[256];
	char sTime[256];
	FormatTime(sTime, sizeof(sTime), "%Y%m%d");
	BuildPath(Path_SM, FileName, sizeof(FileName), "logs/reverse_ff_debug_%s.log", sTime);
	file = OpenFile(FileName, "a+");
	FormatTime(sTime, sizeof(sTime), "%m/%d/%Y - %H:%M:%S");
	WriteFileLine(file, "%s: %s", sTime, buffer);
	FlushFile(file);
	CloseHandle(file);
}

stock void LogCommand(const char[] format, any:...) {
	char buffer[512];
	VFormat(buffer, sizeof(buffer), format, 2);
	Handle file;
	char FileName[256];
	char sTime[256];
	FormatTime(sTime, sizeof(sTime), "%Y%m%d");
	BuildPath(Path_SM, FileName, sizeof(FileName), "logs/reverse_ff_%s.log", sTime);
	file = OpenFile(FileName, "a+");
	FormatTime(sTime, sizeof(sTime), "%m/%d/%Y - %H:%M:%S");
	WriteFileLine(file, "%s: %s", sTime, buffer);
	FlushFile(file);
	CloseHandle(file);
}
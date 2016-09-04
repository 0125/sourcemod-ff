/*
OnTakeDamage
	cons:
		In l4d2 if a survivor is smokered and gets shot without taking damage OnTakeDamage still reports damage
		
OnTakeDamageAlive
	cons:
		If a survivor gets incapped in 1 shot, for example when 1 health, OnTakeDamageAlive does not trigger
*/

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

#pragma newdecls required

//Various global variables
int DamageCache[MAXPLAYERS+1][MAXPLAYERS+1]; //Used to temporarily store Friendly Fire Damage between teammates
Handle FFTimer[MAXPLAYERS+1]; //Used to be able to disable the FF timer when they do more FF
bool FFActive[MAXPLAYERS+1]; //Stores whether players are in a state of friendly firing teammates

int immuneStatus[MAXPLAYERS+1]; //Used to store immune status while & after survivor is under attack from SI
int carryStatus[MAXPLAYERS+1]; //Used to store if survivor is being carried by charger
int pummelStatus[MAXPLAYERS+1]; //Used to store if survivor is being pumelled by charger

char sGame[256];

// cvars and their cached variables
Handle reverse_ff_enable = null;

public Plugin myinfo =
{
	name = "Reverse Friendly Fire",
	author = "Me",
	description = "Reverses Friendly Fire",
	version = "1.0",
	url = "http://www.sourcemod.net/"
};

public void OnPluginStart()
{
	GetGameFolderName(sGame, sizeof(sGame));
	
	reverse_ff_enable = CreateConVar("reverse_ff_enable", "1", "Enable reversed friendy fire");
	AutoExecConfig(true, "reverse_ff");
	
	// hook OnTakeDamage for clients on server
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			SDKHook(i, SDKHook_OnTakeDamage, OnTakeDamage);
		}
	}
	
	// hook SI events to set player immunity from ff
	if (StrEqual(sGame, "left4dead", false) || StrEqual(sGame, "left4dead2", false))
	{
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

public void OnClientPostAdminCheck(int client)
{ // hook OnTakeDamage for new clients after connecting to server
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public void OnClientDisconnect(int client)
{
	SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3])
{
	if (!GetConVarBool(reverse_ff_enable)) // Turned off in config
	{
		return Plugin_Continue;
	}
	
	int victimDmg = RoundToNearest(damage);
	int victimDmgRemaining = victimDmg
	
	if ( (!IsValidEntity(victim)) || (!IsValidEntity(attacker)) ) // is victim or attacker an invalid entity?
	{
		// PrintToChatAll("victim or attacker an invalid entity")
		return Plugin_Continue
	}
	
	if ( (!IsValidClient(attacker)) || (!IsValidClient(attacker)) ) // is victim or attacker an invalid client?
	{
		// PrintToChatAll("victim or attacker an invalid client")
		return Plugin_Continue
	}
	
	if ( (GetClientTeam(victim) != GetClientTeam(attacker)) ) // are victim & attacker not on the same team?
	{
		// PrintToChatAll("victim is not on the same team as attacker")
		return Plugin_Continue
	}
	
	if (immuneStatus[victim] == 1  && GetClientTeam(victim) == GetClientTeam(attacker))
	{
		// PrintToChatAll("victim is immune from cooldown of SI and attacker is on the same team")
		return Plugin_Handled; // do not apply damage to victim or attacker
	}
	
	if (IsPlayerIncapped(attacker))
	{
		// PrintToChatAll("attacker is incapped")
		return Plugin_Handled; // do not apply damage to victim or attacker
	}

	if (attacker == victim) // is damage inflicted to self?
	{
		// PrintToChatAll("damage inflicted to self")
		return Plugin_Continue
	}
	
	// damage inflicted indirectly eg: pipebomb or propanetank explosion
	if (StrEqual(sGame, "left4dead", false))
	{
		if ( !IsValidClient(inflictor) ) // L4D2 melee weapons have random high non-client values
		{
			// PrintToChatAll("l4d1: damage inflicted indirectly")
			return Plugin_Continue
		}
	}
	else if (StrEqual(sGame, "left4dead2", false))
	{
		char attackerWeapon[64];
		GetClientWeapon(attacker, attackerWeapon, sizeof(attackerWeapon)) 
		if ( !StrEqual(attackerWeapon, "weapon_grenade_launcher") ) // if player not using a grenade launcher
		{
			if (weapon == -1) // L4D1 always has -1 weapon
			{
				// PrintToChatAll("l4d2: damage inflicted indirectly")
				return Plugin_Continue
			}
		}
	}
	
	if (IsFakeClient(victim)) // is victim a bot?
	{
		// PrintToChatAll("damage inflicted to bot")
		return Plugin_Continue
	}
	
	// if (CheckCommandAccess(attacker, "root_admin", ADMFLAG_ROOT, true)) // if user is root admin
	// {
		// PrintToChatAll("damage inflicted by root admin")
		// return Plugin_Continue
	// }
	
	// if (GetUserAdmin(attacker) != INVALID_ADMIN_ID) // if user is an admin
	// {
		// PrintToChatAll("damage inflicted by an admin")
		// return Plugin_Continue
	// }
	
	// Punish the attacker
	if( IsPlayerAlive(attacker) && IsClientInGame(attacker) )
	{
		int AttackerHealth = GetClientHealth(attacker);
		int AttackerTempHealth = GetTempHealth(attacker);
		
		if (AttackerHealth - victimDmgRemaining >= 1)
		{
			SetEntityHealth(attacker, AttackerHealth - victimDmgRemaining)
			victimDmgRemaining -= victimDmgRemaining
		}
		if (AttackerHealth - victimDmgRemaining < 1)
		{
			victimDmgRemaining -= AttackerHealth
		}
		
		if (AttackerTempHealth != 0)
		{
			if (AttackerTempHealth - victimDmgRemaining >= 1)
			{
				SetTempHealth(attacker, AttackerTempHealth - victimDmgRemaining)
				victimDmgRemaining -= victimDmgRemaining
			}
			if (AttackerTempHealth - victimDmgRemaining < 1)
			{
				SetTempHealth(attacker, AttackerTempHealth - victimDmgRemaining)
				victimDmgRemaining -= AttackerTempHealth
			}
		}
		
		if (victimDmgRemaining >= 1)
		{
			IncapPlayer(attacker)
			victimDmgRemaining -= 1
			
			SetEntityHealth(attacker, GetClientHealth(attacker) - victimDmgRemaining)
			victimDmgRemaining -= victimDmgRemaining
		}
	}
	
	// Announce
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
	
	return Plugin_Handled; // do not apply damage to victim
}

public Action AnnounceFF(Handle timer, Handle pack) //Called if the attacker did not friendly fire recently, and announces all FF they did
{
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
	
	/*
	for (int i = 1; i < MaxClients; i++)
	{
		if (DamageCache[attackerc][i] != 0 && attackerc != i)
		{
			if (IsClientInGame(i) && IsClientConnected(i))
			{
				GetClientName(i, victim, sizeof(victim));
				
				if (IsClientInGame(attackerc) && IsClientConnected(attackerc) && !IsFakeClient(attackerc))
					PrintToChat(attackerc, "Reversed %d damage you did to %s",DamageCache[attackerc][i],victim);
				if (IsClientInGame(i) && IsClientConnected(i) && !IsFakeClient(i))
					PrintToChat(i, "Reversed %d damage %s did to you",DamageCache[attackerc][i],attacker);
			}
			DamageCache[attackerc][i] = 0;
		}
	}
	*/
}

stock float GetClientsDistance(int victim, int attacker)
{
	float attackerPos[3];
	float victimPos[3];
	float mins[3];
	float maxs[3];
	float halfHeight;
	GetClientMins(victim, mins);
	GetClientMaxs(victim, maxs);
	
	halfHeight = maxs[2] - mins[2] + 10;
	
	GetClientAbsOrigin(victim,victimPos);
	GetClientAbsOrigin(attacker,attackerPos);
	
	float posHeightDiff = attackerPos[2] - victimPos[2];
	
	if (posHeightDiff > halfHeight)
	{
		attackerPos[2] -= halfHeight;
	}
	else if (posHeightDiff < (-1.0 * halfHeight))
	{
		victimPos[2] -= halfHeight;
	}
	else
	{
		attackerPos[2] = victimPos[2];
	}
	
	return GetVectorDistance(victimPos ,attackerPos, false);
}

bool IsPlayerIncapped(int client)
{
	if (GetEntProp(client, Prop_Send, "m_isIncapacitated", 1)) 
		return true;
	else
		return false;
}

int GetTempHealth(int client)
{
	float decay = GetConVarFloat(FindConVar("pain_pills_decay_rate"));
	float buffer = GetEntPropFloat(client, Prop_Send, "m_healthBuffer");
	float time = (GetGameTime() - GetEntPropFloat(client, Prop_Send, "m_healthBufferTime"));
	float TempHealth = buffer - (time * decay)
	if (TempHealth < 0) return 0;
	else return RoundToFloor(TempHealth);
}

int SetTempHealth(int client, int hp)
{
	SetEntPropFloat(client, Prop_Send, "m_healthBufferTime", GetGameTime());
	float TempHealthFloat = hp * 1.0 //prevent tag mismatch
	SetEntPropFloat(client, Prop_Send, "m_healthBuffer", TempHealthFloat);
}

void IncapPlayer(int client)
{
	/*
	using DamageType 32 (fall damage) instead of 0 (generic damage)
	prevents a bug where if the attacker does a lot of damage to the victim rapidly,
	for example shooting point blank multiple times with a high damage weapon on expert difficulty,
	the attacker is not affected by the point_hurt entity created in this function
	https://developer.valvesoftware.com/wiki/Point_hurt
	*/
	
	if(IsValidEntity(client))
	{
		int iDmgEntity = CreateEntityByName("point_hurt");
		SetEntityHealth(client, 1);
		SetTempHealth(client, 0) // prevents l4d1 server error msg spam: DataTable warning: (class player): Out-of-range value (-XX.000000) in SendPropFloat 'm_healthBuffer', clamping.
		DispatchKeyValue(client, "targetname", "bm_target");
		DispatchKeyValue(iDmgEntity, "DamageTarget", "bm_target");
		DispatchKeyValue(iDmgEntity, "Damage", "100");
		DispatchKeyValue(iDmgEntity, "DamageType", "32");
		DispatchSpawn(iDmgEntity);
		AcceptEntityInput(iDmgEntity, "Hurt", client);
		DispatchKeyValue(client, "targetname", "bm_targetoff");
		RemoveEdict(iDmgEntity);
	}
}

bool IsValidClient(int client) 
{
    if ( !( 1 <= client <= MaxClients ) || !IsClientInGame(client) ) 
        return false; 
     
    return true; 
}

public Action Event_immunityStart(Handle event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "victim"));
	if (!IsSurvivor(client))
	{
		return;
	}
	// PrintToChatAll("Event_immunityStart: immuneStatus 1");
	immuneStatus[client] = 1
}

public Action Event_immunityEnd(Handle event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "victim"));
	if (!IsSurvivor(client))
	{
		return;
	}
	
	// PrintToChatAll("Event_immunityEnd: starting Timer_immunityEnd");
	
	CreateTimer(2.0, Timer_immunityEnd, client);
}

public Action Event_charger_carry_start(Handle event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "victim"));
	if (!IsSurvivor(client))
	{
		return;
	}
	
	// PrintToChatAll("Event_charger_carry_start");
	carryStatus[client] = 1
	immuneStatus[client] = 1
}

public Action Event_charger_carry_end(Handle event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "victim"));
	if (!IsSurvivor(client))
	{
		return;
	}
	
	// PrintToChatAll("Event_charger_carry_end: starting Timer_immunityEnd");
	carryStatus[client] = 0
	CreateTimer(2.0, Timer_immunityEnd, client);
}

public Action Event_charger_pummel_start(Handle event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "victim"));
	if (!IsSurvivor(client))
	{
		return;
	}
	
	// PrintToChatAll("Event_charger_pummel_start");
	pummelStatus[client] = 1
	immuneStatus[client] = 1
}

public Action Event_charger_pummel_end(Handle event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "victim"));
	if (!IsSurvivor(client))
	{
		return;
	}
	
	// PrintToChatAll("Event_charger_pummel_end: starting Timer_immunityEnd");
	pummelStatus[client] = 0
	CreateTimer(2.0, Timer_immunityEnd, client);
}

public Action Timer_immunityEnd(Handle timer, any client)
{
	if (carryStatus[client] == 1 || pummelStatus[client] == 1) // do not remove immunity if victim is being carried or pummeled by charger
	{
		// PrintToChatAll("Timer_immunityEnd: survivor is being pummeled or carried");
		return;
	}
	
	// PrintToChatAll("Timer_immunityEnd: immuneStatus 0!");
	immuneStatus[client] = 0
}

stock bool IsSurvivor(int client)
{
	if (client > 0 && client < MaxClients && IsClientInGame(client) && GetClientTeam(client) == 2)
	{
		return true;
	}
	return false;
} 
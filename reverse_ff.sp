#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

#pragma newdecls required

public Plugin myinfo =
{
	name = "Reverse Friendly Fire",
	author = "Me",
	description = "Reverses Friendly Fire",
	version = "1.0",
	url = "http://www.sourcemod.net/"
};

public void OnClientPostAdminCheck(int client)
{
	// char ClientName[64];
	// GetClientName(client, ClientName, sizeof(ClientName))
	// PrintToChatAll("OnClientPostAdminCheck(): %s", ClientName)
	
	SDKHook(client, SDKHook_OnTakeDamageAlive, OnTakeDamageAlive);
}

public void OnPluginStart()
{
	// PrintToChatAll("OnPluginStart()")
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			// char ClientName[64];
			// GetClientName(i, ClientName, sizeof(ClientName))
			// PrintToChatAll("OnClientPostAdminCheck(): %s", ClientName)
			
			SDKHook(i, SDKHook_OnTakeDamageAlive, OnTakeDamageAlive);
		}
	}
}

/*
OnTakeDamageAlive damage is more accurate than OnTakeDamage, for example:
In l4d2 a survivor is smokered. Gets shot without taking damage, but
OnTakeDamage thinks there was damage done
*/
public Action OnTakeDamageAlive(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3])
{
	int VictimId = victim;
	int AttackerId = attacker;
	int VictimDmg = RoundToNearest(damage);
	int VictimDmgRemaining = VictimDmg
	
	char VictimName[64];
	char AttackerName[64];
	char AttackerWeapon[64];
	
	/*
	PrintToServer("victim: %d", victim)
	PrintToServer("attacker: %d", attacker)
	PrintToServer("inflictor: %d", inflictor)
	PrintToServer("damage: %f", damage)
	PrintToServer("damagetype: %d", damagetype)
	PrintToServer("weapon: %d", weapon)
	PrintToServer("damageForce: %f", damageForce)
	PrintToServer("damagePosition: %f", damagePosition)
	*/
	
	if ( (!IsValidEntity(VictimId)) || (!IsValidEntity(AttackerId)) ) // are victim & attacker invalid entities?
	{
		// PrintToChatAll("invalid Victim or attacker Id")
		return Plugin_Continue
	}
	
	if ( (!IsValidClient(AttackerId)) || (!IsValidClient(AttackerId)) ) // are victim & attacker invalid clients?
	{
		// PrintToChatAll("Victim or attacker is not a valid client")
		return Plugin_Continue
	}
	
	// Get client info after valid client check. Using an invalid client id for certain GetClient fuctions causes an error and stops flow
	GetClientName(VictimId, VictimName, sizeof(VictimName))
	GetClientName(AttackerId, AttackerName, sizeof(AttackerName))
	GetClientWeapon(AttackerId, AttackerWeapon, sizeof(AttackerWeapon)) 
	
	if (IsPlayerIncapped(AttackerId))
	{
		// PrintToChatAll("attacker is incapped")
		return Plugin_Handled; // do not apply damage to victim
	}
	
	if ( (GetClientTeam(VictimId) != GetClientTeam(AttackerId)) ) // are victim & attacker not on the same team?
	{
		// PrintToChatAll("victim is not on the same team as attacker")
		return Plugin_Continue
	}

	if (AttackerId == VictimId) // is damage inflicted to self?
	{
		// PrintToChatAll("damage inflicted to self")
		return Plugin_Continue
	}

	if (IsFakeClient(VictimId)) // is victim a bot?
	{
		// PrintToChatAll("damage inflicted to bot")
		return Plugin_Continue
	}
	
	// damage inflicted indirectly eg: pipebomb or propanetank explosion
	char sGame[256];
	GetGameFolderName(sGame, sizeof(sGame));
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
		if ( !StrEqual(AttackerWeapon, "weapon_grenade_launcher") ) // player not using a grenade launcher
		{
			if (weapon == -1) // L4D1 always has -1 weapon
			{
				// PrintToChatAll("l4d2: damage inflicted indirectly")
				return Plugin_Continue
			}
		}
	}
	
	if (CheckCommandAccess(AttackerId, "root_admin", ADMFLAG_ROOT, true)) // if user is root admin
	{
		// PrintToChatAll("damage inflicted by root admin")
		return Plugin_Continue
	}
	
	// if (GetUserAdmin(AttackerId) != INVALID_ADMIN_ID) // if user is an admin
	// {
		// PrintToChatAll("damage inflicted by an admin")
		// return Plugin_Continue
	// }
	
	if (VictimDmg == 0) // was there any actual damage done
	{
		// PrintToChatAll("zero damage done")
		return Plugin_Continue
	}
	
	// PrintToChatAll("Prevented %s hitting %s for %d damage", AttackerName, VictimName, VictimDmg)
	
	// Punish the attacker
	if( IsPlayerAlive(AttackerId) && IsClientInGame(AttackerId) )
	{
		int AttackerHealth = GetClientHealth(AttackerId);
		int AttackerTempHealth = GetTempHealth(AttackerId);
		
		int AttackerHealthAfterReverse = (AttackerHealth + AttackerTempHealth) - VictimDmg
		// PrintToChatAll("Set %s's health to %d", AttackerName, AttackerHealthAfterReverse)
		
		int myFloatingVar = (GetEntProp(VictimId, Prop_Send, "m_iPlayerState", 1))
		// PrintToChatAll("m_iPlayerState: %d", myFloatingVar)p
		
		if (AttackerHealth - VictimDmgRemaining >= 1)
		{
			SetEntityHealth(AttackerId, AttackerHealth - VictimDmgRemaining)
			VictimDmgRemaining -= VictimDmgRemaining
		}
		if (AttackerHealth - VictimDmgRemaining < 1)
		{
			VictimDmgRemaining -= AttackerHealth
		}
		
		if (AttackerTempHealth != 0)
		{
			if (AttackerTempHealth - VictimDmgRemaining >= 1)
			{
				SetTempHealth(AttackerId, AttackerTempHealth - VictimDmgRemaining)
				VictimDmgRemaining -= VictimDmgRemaining
			}
			if (AttackerTempHealth - VictimDmgRemaining < 1)
			{
				SetTempHealth(AttackerId, AttackerTempHealth - VictimDmgRemaining)
				VictimDmgRemaining -= AttackerTempHealth
			}
		}
		
		if (VictimDmgRemaining >= 1)
		{
			IncapPlayer(AttackerId)
			VictimDmgRemaining -= 1
			
			if (IsPlayerIncapped(AttackerId)) // check if player is incapped, incase IncapPlayer() failed. possible when a survivor with 100/high health starts spamming hunting rifle or another high damage weapon at someone
			{
				SetEntityHealth(AttackerId, 300 - VictimDmgRemaining)
				VictimDmgRemaining -= VictimDmgRemaining
			}
		}
	}

	return Plugin_Handled; // do not apply damage to victim
}

bool IsPlayerIncapped(int client)
{
	if (GetEntProp(client, Prop_Send, "m_isIncapacitated", 1)) 
		return true;
	else
		return false;
}
bool IsPlayerGrapEdge(int client)
{
 	if (GetEntProp(client, Prop_Send, "m_isHangingFromLedge", 1))
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

void IncapPlayer(int target)
{
	if(IsValidEntity(target))
	{
		int iDmgEntity = CreateEntityByName("point_hurt");
		SetEntityHealth(target, 1);
		DispatchKeyValue(target, "targetname", "bm_target");
		DispatchKeyValue(iDmgEntity, "DamageTarget", "bm_target");
		DispatchKeyValue(iDmgEntity, "Damage", "100");
		DispatchKeyValue(iDmgEntity, "DamageType", "0");
		DispatchSpawn(iDmgEntity);
		AcceptEntityInput(iDmgEntity, "Hurt", target);
		DispatchKeyValue(target, "targetname", "bm_targetoff");
		RemoveEdict(iDmgEntity);
	}
}

bool IsValidClient(int client) 
{
    if ( !( 1 <= client <= MaxClients ) || !IsClientInGame(client) ) 
        return false; 
     
    return true; 
}
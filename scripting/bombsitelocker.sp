#pragma semicolon 1 
#pragma newdecls required 

#include <sourcemod>
#include <sdktools> 
#include <cstrike> 

public Plugin myinfo =
{
    name = "Bombsite Locker",
    author = "Ilusion9",
    description = "Disable bombsite A or B if there are fewer CTs than the accepted limit",
    version = "2.1",
    url = "https://github.com/Ilusion9/"
};

ConVar g_Cvar_FreezeTime;
Handle g_Timer_FreezeEnd;

int g_SiteLimit;
char g_SiteLocked;

public void OnPluginStart()
{
	LoadTranslations("bombsitelocker.phrases");
	
	HookEvent("round_start", Event_RoundStart);	
	g_Cvar_FreezeTime = FindConVar("mp_freezetime");
}

public void OnMapStart()
{
	g_SiteLimit = 0;
	g_SiteLocked = 0;
}

public void OnMapEnd()
{
	delete g_Timer_FreezeEnd;
}

public void OnConfigsExecuted()
{
	char path[PLATFORM_MAX_PATH];	
	BuildPath(Path_SM, path, sizeof(path), "configs/bombsitelocker.cfg");
	
	KeyValues kv = new KeyValues("BombsiteLocker"); 
	if (!kv.ImportFromFile(path))
	{
		SetFailState("The configuration file could not be read.");
	}
	
	char map[PLATFORM_MAX_PATH];
	GetCurrentMap(map, sizeof(map));
	
	if (kv.JumpToKey(map)) 
	{
		char key[64];
		
		kv.GetString("site_locked", key, sizeof(key));
		g_SiteLocked = CharToUpper(key[0]);
		
		if (g_SiteLocked != 'A' && g_SiteLocked != 'B')
		{
			g_SiteLocked = 0;
		}
		
		g_SiteLimit = kv.GetNum("ct_limit", 0);
	}
	
	delete kv;
	
	/* Players should not be spawned after the freeze time ends */
	if (g_SiteLocked)
	{
		FindConVar("mp_join_grace_time").SetInt(0);
	}
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast) 
{
	delete g_Timer_FreezeEnd;
	
	if (GameRules_GetProp("m_bWarmupPeriod"))
	{
		return;
	}
	
	if (g_SiteLocked)
	{
		g_Timer_FreezeEnd = CreateTimer(g_Cvar_FreezeTime.FloatValue + 1.0, Timer_HandleFreezeEnd);
	}
}

/* Original code from: https://forums.alliedmods.net/showthread.php?t=136912 */
public Action Timer_HandleFreezeEnd(Handle timer, any data)
{
	int siteA = -1, siteB = -1;
	int ent = FindEntityByClassname(-1, "cs_player_manager");
	
	if (ent != -1)
	{
		/* Get bombsites coordinates from players radar */
		float bombsiteCenterA[3], bombsiteCenterB[3];
		
		GetEntPropVector(ent, Prop_Send, "m_bombsiteCenterA", bombsiteCenterA); 
		GetEntPropVector(ent, Prop_Send, "m_bombsiteCenterB", bombsiteCenterB);
		
		/* Find which site is A and which is B by checking those coordinates */
		ent = -1;
		
		while ((ent = FindEntityByClassname(ent, "func_bomb_target")) != -1)
		{
			float vecMins[3], vecMaxs[3];
			
			GetEntPropVector(ent, Prop_Send, "m_vecMins", vecMins); 
			GetEntPropVector(ent, Prop_Send, "m_vecMaxs", vecMaxs);
			
			if (IsVecBetween(bombsiteCenterA, vecMins, vecMaxs))
			{
				siteA = ent; 
			}
			
			else if (IsVecBetween(bombsiteCenterB, vecMins, vecMaxs))
			{
				siteB = ent;
			}
			
			AcceptEntityInput(ent, "Enable");
		}
	}
	
	if (siteA != -1 && siteB != -1)
	{
		if (GetCounterTerroristsCount() < g_SiteLimit)
		{
			AcceptEntityInput(g_SiteLocked != 'A' ? siteB : siteA, "Disable");	

			PrintToChatAll("%t", "Bombsite Disabled Reason", g_SiteLocked, g_SiteLimit);
			PrintCenterTextAll("%t", "Bombsite Disabled", g_SiteLocked);
		}
	}
	
	g_Timer_FreezeEnd = null;
	return Plugin_Continue;
}

bool IsVecBetween(const float vec[3], const float mins[3], const float maxs[3]) 
{
	for (int i = 0; i < 3; i++)
	{
		if (vec[i] < mins[i] || vec[i] > maxs[i])
		{
			return false;
		}
	}
	
	return true;
}

int GetCounterTerroristsCount()
{
	int num;
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == CS_TEAM_CT)
		{
			num++;
		}
	}

	return num;
}

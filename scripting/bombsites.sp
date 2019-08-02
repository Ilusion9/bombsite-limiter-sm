#pragma semicolon 1 
#pragma newdecls required 

#include <sourcemod>
#include <sdktools> 
#include <cstrike> 

public Plugin myinfo =
{
    name = "Bombsite Limiter",
    author = "Ilusion9",
    description = "Disable bombsite A or B if there are fewer CTs than the accepted limit",
    version = "2.0",
    url = "https://github.com/Ilusion9/"
};

enum Sites
{
	SITE_NONE = 0,
	SITE_A,
	SITE_B
};

int g_BombsiteLimit;
Sites g_BombsiteToLock;

public void OnPluginStart() 
{
	LoadTranslations("bombsites.phrases");
	HookEvent("round_freeze_end", Event_RoundFreezeEnd);
}

public void OnMapStart()
{
	g_BombsiteLimit = 0;
	g_BombsiteToLock = SITE_NONE;
}

public void OnConfigsExecuted()
{
	char map[PLATFORM_MAX_PATH], path[PLATFORM_MAX_PATH];
	KeyValues kv = new KeyValues("BombSites"); 

	GetCurrentMap(map, sizeof(map));
	BuildPath(Path_SM, path, sizeof(path), "configs/bombsites.cfg");
	
	if (!kv.ImportFromFile(path)) 
	{
		SetFailState("The configuration file could not be read.");
	}
	
	if (kv.JumpToKey(map)) 
	{
		char key[64];
		kv.GetString("site_locked", key, sizeof(key));
		
		if (StrEqual(key, "A", false))
		{
			g_BombsiteToLock = SITE_A;
		}
		
		else if (StrEqual(key, "B", false))
		{
			g_BombsiteToLock = SITE_B;
		}
		
		g_BombsiteLimit = kv.GetNum("ct_limit", 0);
	}
	
	delete kv;
	
	if (g_BombsiteToLock != SITE_NONE)
	{
		/* Players should not spawn after the freeze time ends */
		ConVar cvar = FindConVar("mp_join_grace_time"); 

		if (cvar)
		{
			cvar.IntValue = 0; 
		}
	}
}

public void Event_RoundFreezeEnd(Event event, const char[] name, bool dontBroadcast) 
{
	if (GameRules_GetProp("m_bWarmupPeriod"))
	{
		return;
	}
	
	RequestFrame(OnFreezeTimeEnd);
}

public void OnFreezeTimeEnd(any data)
{
	if (g_BombsiteToLock != SITE_NONE)
	{		
		int siteA = -1, siteB = -1;
		int ent = FindEntityByClassname(-1, "cs_player_manager");

		if (ent != -1)
		{
			float posA[3], posB[3];
			
			GetEntPropVector(ent, Prop_Send, "m_bombsiteCenterA", posA); 
			GetEntPropVector(ent, Prop_Send, "m_bombsiteCenterB", posB);
			
			ent = -1;
			while ((ent = FindEntityByClassname(ent, "func_bomb_target")) != -1)
			{
				float vecMins[3], vecMaxs[3];
				
				GetEntPropVector(ent, Prop_Send,"m_vecMins", vecMins); 
				GetEntPropVector(ent, Prop_Send,"m_vecMaxs", vecMaxs);
				
				if (IsVecBetween(posA, vecMins, vecMaxs)) 
				{
					siteA = ent; 
				}
				
				else if (IsVecBetween(posB, vecMins, vecMaxs)) 
				{
					siteB = ent; 
				}
				
				AcceptEntityInput(siteA, "Enable");
			}
		}
		
		if (siteA != -1 && siteB != -1)
		{
			if (GetCounterTerroristsCount() < g_BombsiteLimit)
			{
				switch (g_BombsiteToLock)
				{
					case SITE_A:
					{
						AcceptEntityInput(siteA, "Disable");	
					
						PrintToChatAll(" \x04[SITE]\x01 %t", "Bombsite Disabled Reason", "A", g_BombsiteLimit);
						PrintCenterTextAll("%t", "Bombsite Disabled", "A");
					}
					
					case SITE_B:
					{
						AcceptEntityInput(siteB, "Disable");	
						
						PrintToChatAll(" \x04[SITE]\x01 %t", "Bombsite Disabled Reason", "B", g_BombsiteLimit);
						PrintCenterTextAll("%t", "Bombsite Disabled", "B");
					}
				}
			}
		}
	}
}

stock bool IsVecBetween(const float vecVector[3], const float vecMin[3], const float vecMax[3]) 
{
	return ((vecMin[0] <= vecVector[0] <= vecMax[0]) && (vecMin[1] <= vecVector[1] <= vecMax[1]) && (vecMin[2] <= vecVector[2] <= vecMax[2])); 
}

stock int GetCounterTerroristsCount()
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
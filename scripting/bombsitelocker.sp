#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <colorlib>

#pragma newdecls required

public Plugin myinfo =
{
	name = "Bombsite Locker",
	author = "Ilusion9",
	description = "Disable specified bombsites if there are fewer CTs than their accepted limit",
	version = "3.0",
	url = "https://github.com/Ilusion9/"
};

#define MAX_BOMBSITES	10
enum struct SiteInfo
{
	int EntityId;
	int HammerId;
	char Letter;
	int LimitCT;
}

enum ChangeState
{
	Not_Changing,
	Changing_Letter,
	Changing_Limit
}

ConVar g_Cvar_FreezeTime;
Handle g_Timer_FreezeEnd;

SiteInfo g_BombSites[MAX_BOMBSITES];
int g_NumOfBombSites;

ChangeState g_ChangingSettings[MAXPLAYERS + 1];
int g_SelectedBombSite[MAXPLAYERS + 1];

public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("bombsitelocker.phrases");
	
	RegAdminCmd("sm_bombsites", Command_Bombsites, ADMFLAG_RCON);
	
	HookEvent("round_start", Event_RoundStart);	
	g_Cvar_FreezeTime = FindConVar("mp_freezetime");
}

public void OnMapStart()
{
	g_NumOfBombSites = 0;
	int entity = -1;
	
	while ((entity = FindEntityByClassname(entity, "func_bomb_target")) != -1)
	{
		g_BombSites[g_NumOfBombSites].EntityId = entity;
		g_BombSites[g_NumOfBombSites].HammerId = GetEntityHammerId(entity);
		g_BombSites[g_NumOfBombSites].Letter = 0;
		g_BombSites[g_NumOfBombSites].LimitCT = 0;
		g_NumOfBombSites++;
	}
}

public void OnConfigsExecuted()
{
	char map[PLATFORM_MAX_PATH], path[PLATFORM_MAX_PATH];	
	GetCurrentMap(map, sizeof(map));
	
	BuildPath(Path_SM, path, sizeof(path), "configs/bombsite_locker/%s.sites.cfg", map);
	KeyValues kv = new KeyValues("Bombsites");
	
	if (kv.ImportFromFile(path))
	{
		if (kv.GotoFirstSubKey(false))
		{
			do
			{
				char section[65];
				kv.GetSectionName(section, sizeof(section));
				int hammerId = StringToInt(section);
				
				for (int i = 0; i < g_NumOfBombSites; i++)
				{
					if (g_BombSites[i].HammerId == hammerId)
					{
						char letter[3];
						kv.GetString("letter", letter, sizeof(letter), "\n");
						g_BombSites[i].Letter = CharToUpper(letter[0]);
						
						if (!IsCharAlpha(g_BombSites[i].Letter))
						{
							g_BombSites[i].Letter = 0;
							g_BombSites[i].LimitCT = 0;
							LogError("Invalid letter specified for section \"%d\" (map: \"%s\")", hammerId, map);
							break;
						}
						
						g_BombSites[i].LimitCT = kv.GetNum("ct_limit", 0);
						if (g_BombSites[i].LimitCT < 1)
						{
							g_BombSites[i].Letter = 0;
							g_BombSites[i].LimitCT = 0;
							LogError("Invalid limit of CTs specified for section \"%d\" (map: \"%s\")", hammerId, map);
						}
						
						break;
					}
				}
				
			} while (kv.GotoNextKey(false));
		}
	}
	
	delete kv;
	SetConVar("mp_join_grace_time", "0");
}

public void OnMapEnd()
{
	delete g_Timer_FreezeEnd;
	
	char map[PLATFORM_MAX_PATH], path[PLATFORM_MAX_PATH];	
	GetCurrentMap(map, sizeof(map));
	
	BuildPath(Path_SM, path, sizeof(path), "configs/bombsite_locker");
	if (!DirExists(path))
	{
		CreateDirectory(path, 0777);
	}
	
	BuildPath(Path_SM, path, sizeof(path), "configs/bombsite_locker/%s.sites.cfg", map);
	KeyValues kv = new KeyValues("Bombsites");
	kv.ImportFromFile(path);
	
	for (int i = 0; i < g_NumOfBombSites; i++)
	{
		char key[65];
		Format(key, sizeof(key), "%d", g_BombSites[i].HammerId);
		
		if (!g_BombSites[i].Letter || !g_BombSites[i].LimitCT)
		{
			if (kv.JumpToKey(key))
			{
				kv.DeleteThis();
				kv.GoBack();
			}
			
			continue;
		}
		
		kv.JumpToKey(key, true);
		char letter[3];
		Format(letter, sizeof(letter), "%c", g_BombSites[i].Letter);
		
		kv.SetString("letter", letter);
		kv.SetNum("ct_limit", g_BombSites[i].LimitCT);		
		kv.GoBack();
	}
	
	kv.ExportToFile(path);
	delete kv;
}

public void OnClientConnected(int client)
{
	g_ChangingSettings[client] = Not_Changing;
}

public void OnClientDisconnect_Post(int client)
{
	g_ChangingSettings[client] = Not_Changing;
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast) 
{
	delete g_Timer_FreezeEnd;
	
	if (IsWarmupPeriod())
	{
		return;
	}
	
	g_Timer_FreezeEnd = CreateTimer(g_Cvar_FreezeTime.FloatValue + 1.0, Timer_HandleFreezeEnd);
}

public Action Timer_HandleFreezeEnd(Handle timer, any data)
{
	int numOfCTs = GetCounterTerroristsCount();
	for (int i = 0; i < g_NumOfBombSites; i++)
	{
		AcceptEntityInput(g_BombSites[i].EntityId, "Enable");
		
		if (!g_BombSites[i].LimitCT || !g_BombSites[i].Letter)
		{
			continue;
		}
		
		if (numOfCTs < g_BombSites[i].LimitCT)
		{
			AcceptEntityInput(g_BombSites[i].EntityId, "Disable");
			CPrintToChatAll("> %t", "Bombsite Disabled Reason", g_BombSites[i].Letter, g_BombSites[i].LimitCT);
		}
	}
	
	g_Timer_FreezeEnd = null;
}

public Action Command_Bombsites(int client, int args)
{
	if (!client)
	{
		ReplyToCommand(client, "[SM] %t", "Command is in-game only");
		return Plugin_Handled;
	}
	
	if (!g_NumOfBombSites)
	{
		CReplyToCommand(client, "[SM] %t", "Map Without Bombsites");
		return Plugin_Handled;
	}
	
	ShowBombSitesMenu(client);
	return Plugin_Handled;
}

void ShowBombSitesMenu(int client)
{
	Menu menu = new Menu(Menu_BombSitesHandler);
	menu.SetTitle("%T", "Bombsites", client);
	
	for (int i = 0; i < g_NumOfBombSites; i++)
	{
		char buffer[65];
		Format(buffer, sizeof(buffer), "%T", "Bombsite Number", client, i + 1);
		menu.AddItem("", buffer);
	}
	
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Menu_BombSitesHandler(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_End:
		{
			delete menu;
		}
		
		case MenuAction_Select:
		{
			g_SelectedBombSite[param1] = param2;
			ShowOptionsMenu(param1);
		}
	}
}

void ShowOptionsMenu(int client)
{
	char buffer[65];
	int option = g_SelectedBombSite[client];
	Menu menu = new Menu(Menu_OptionsHandler);
	
	menu.SetTitle("%T", "Bombsite Number", client, option + 1);
	Format(buffer, sizeof(buffer), "%T", "Teleport To Bombsite", client);
	menu.AddItem("", buffer);
	
	if (g_BombSites[option].Letter)
	{
		Format(buffer, sizeof(buffer), "%T", "Bombsite Change Letter", client, g_BombSites[option].Letter);
	}
	else
	{
		Format(buffer, sizeof(buffer), "%T", "Bombsite Set Letter", client);
	}
	menu.AddItem("", buffer);
	
	if (g_BombSites[option].LimitCT)
	{
		Format(buffer, sizeof(buffer), "%T", "Bombsite Change Limit", client, g_BombSites[option].LimitCT);
	}
	else
	{
		Format(buffer, sizeof(buffer), "%T", "Bombsite Set Limit", client);
	}
	menu.AddItem("", buffer, g_BombSites[option].Letter ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	
	Format(buffer, sizeof(buffer), "%T", "Bombsite Remove Settings", client);
	menu.AddItem("", buffer, g_BombSites[option].LimitCT && g_BombSites[option].Letter ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Menu_OptionsHandler(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_End:
		{
			delete menu;
		}
		
		case MenuAction_Cancel:
		{
			if (g_ChangingSettings[param1] == Changing_Letter)
			{
				CPrintToChat(param1, "[SM] %t", "Action Changing Letter Canceled", g_SelectedBombSite[param1] + 1);
				g_ChangingSettings[param1] = Not_Changing;
			}
			
			else if (g_ChangingSettings[param1] == Changing_Limit)
			{
				CPrintToChat(param1, "[SM] %t", "Action Changing Limit Canceled", g_SelectedBombSite[param1] + 1);
				g_ChangingSettings[param1] = Not_Changing;
			}
			
			if (param2 == MenuCancel_ExitBack)
			{
				ShowBombSitesMenu(param1);
			}
		}
		
		case MenuAction_Select:
		{
			switch (param2)
			{
				case 0:
				{
					int option = g_SelectedBombSite[param1];
					int entity = g_BombSites[option].EntityId;
					
					float position[3], vecMins[3], vecMaxs[3];
					GetEntPropVector(entity, Prop_Send, "m_vecMins", vecMins); 
					GetEntPropVector(entity, Prop_Send, "m_vecMaxs", vecMaxs);
					
					GetMiddleOfABox(vecMins, vecMaxs, position);
					TeleportEntity(param1, position, NULL_VECTOR, NULL_VECTOR);
					
					CPrintToChat(param1, "[SM] %t", "Teleported To Bombsite", g_SelectedBombSite[param1] + 1);
					ShowOptionsMenu(param1);
				}
				
				case 1:
				{
					if (g_ChangingSettings[param1] == Changing_Limit)
					{
						CPrintToChat(param1, "[SM] %t", "Action Changing Limit Canceled", g_SelectedBombSite[param1] + 1);
					}
					
					g_ChangingSettings[param1] = Changing_Letter;
					CPrintToChat(param1, "[SM] %t", "Type Bombsite Letter", g_SelectedBombSite[param1] + 1);
					CPrintToChat(param1, "[SM] %t", "Abort Action");
					ShowOptionsMenu(param1);
				}
				
				case 2:
				{
					if (g_ChangingSettings[param1] == Changing_Letter)
					{
						CPrintToChat(param1, "[SM] %t", "Action Changing Letter Canceled", g_SelectedBombSite[param1] + 1);
					}
					
					g_ChangingSettings[param1] = Changing_Limit;
					CPrintToChat(param1, "[SM] %t", "Type Bombsite Limit", g_SelectedBombSite[param1] + 1);
					CPrintToChat(param1, "[SM] %t", "Abort Action");
					ShowOptionsMenu(param1);
				}
				
				case 3:
				{
					if (g_ChangingSettings[param1] == Changing_Letter)
					{
						CPrintToChat(param1, "[SM] %t", "Action Changing Letter Canceled", g_SelectedBombSite[param1] + 1);
						g_ChangingSettings[param1] = Not_Changing;
					}
					
					else if (g_ChangingSettings[param1] == Changing_Limit)
					{
						CPrintToChat(param1, "[SM] %t", "Action Changing Limit Canceled", g_SelectedBombSite[param1] + 1);
						g_ChangingSettings[param1] = Not_Changing;
					}

					int option = g_SelectedBombSite[param1];
					g_BombSites[option].Letter = 0;
					g_BombSites[option].LimitCT = 0;
					
					CPrintToChat(param1, "[SM] %t", "Bombsite Settings Removed", g_SelectedBombSite[param1] + 1);
					ShowOptionsMenu(param1);
				}
			}
		}
	}
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	if (g_ChangingSettings[client] == Not_Changing)
	{
		return Plugin_Continue;
	}
	
	if (StrEqual(sArgs, "cancel", false))
	{
		g_ChangingSettings[client] = Not_Changing;
		CPrintToChat(client, "[SM] %t", "Bombsite Action Canceled", g_SelectedBombSite[client] + 1);
		return Plugin_Handled;
	}
	
	int option = g_SelectedBombSite[client];
	if (g_ChangingSettings[client] == Changing_Letter)
	{
		char letter = CharToUpper(sArgs[0]);
		if (!IsCharAlpha(letter))
		{
			CPrintToChat(client, "[SM] %t", "Bombsite Invalid Letter");
			CPrintToChat(client, "[SM] %t", "Abort Action");
			return Plugin_Handled;
		}
		
		g_BombSites[option].Letter = letter;
		CPrintToChat(client, "[SM] %t", "Bombsite Letter Changed", option + 1);
	}
	else if (g_ChangingSettings[client] == Changing_Limit)
	{
		int limit;
		if (!StringToIntEx(sArgs[0], limit) || limit < 1)
		{
			CPrintToChat(client, "[SM] %t", "Bombsite Invalid Limit");
			CPrintToChat(client, "[SM] %t", "Abort Action");
			return Plugin_Handled;
		}
		
		g_BombSites[option].LimitCT = limit;
		CPrintToChat(client, "[SM] %t", "Bombsite Limit Changed", option + 1);
	}
	
	g_ChangingSettings[client] = Not_Changing;
	ShowOptionsMenu(client);
	return Plugin_Handled;
}

int GetEntityHammerId(int entity)
{
	return GetEntProp(entity, Prop_Data, "m_iHammerID");
}

bool IsWarmupPeriod()
{
	return view_as<bool>(GameRules_GetProp("m_bWarmupPeriod"));
}

void SetConVar(const char[] name, const char[] value)
{
	ConVar cvar = FindConVar(name);
	if (cvar)
	{
		cvar.SetString(value);
	}
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

/* From https://github.com/Franc1sco/DevZones plugin */
void GetMiddleOfABox(const float vec1[3], const float vec2[3], float result[3])
{
	float mid[3];
	MakeVectorFromPoints(vec1, vec2, mid);
	mid[0] = mid[0] / 2.0;
	mid[1] = mid[1] / 2.0;
	mid[2] = mid[2] / 2.0;
	AddVectors(vec1, mid, result);
}

//Appname:
//SimpleCSGORanks

#include <dbi>
#include <sourcemod> 
#include <cstrike>
#include <clientprefs>
#include <sdktools>
#include <multicolors>
#include <smlib>

#define PLUGIN_VERSION "0.2.2Dev"

//Global Variables, do NOT touch.
bool ready = false;
int shotPlayers = -1;
int defuser = -1; //guy who defused the bomb type is CLIENT!!
int shotCountdown = 0;
Handle dbc;
Handle dbt; //handle for threaded query
char errorc[255];
float copyTime;

int dbLocked = 0;
int rankCache[65]; //Caches ranks for threaded operation (Soon TM)
int rankCacheValidate[65]; //Validation
int cacheCurrentClient = 1;

//Global Variables, you can touch.
int threadedCache = 1; //Experimental optimization. Should drastically improve speeds
int threadedWorker = 1; //Automatically load rank data in the background in another thread to improve speeds
int immediateMode = 1; //Use immediate Worker instead of slow round method. Good for Deathmatch
int ranksText[320];
new String:databaseName[128] = "default";
new String:databaseNew[128] = "default";
new String:databaseCheck[128] = "default";
new String:ranksText2[65][65];
new String:topRanks[50][128];
int shooter[255];//array of clients
int assister[255];//array of clients
int shot[255];

//convars
ConVar sm_simplecsgoranks_kill_points;
ConVar sm_simplecsgoranks_higher_rank_additional;
ConVar sm_simplecsgoranks_higher_rank_gap;

ConVar sm_simplecsgoranks_database;
ConVar sm_simplecsgoranks_cleaning;
ConVar sm_simplecsgoranks_debug;
	

//editable defines
int printToServer = 0;
int higherRankThreshold = 200; //how many points above a user should me considered much higher
int higherRankFactor = 5; //if the shot user is much higher than the user who shot them the higher ranked user should lose more rank.
int killPoints = 5;
int startRank = 100; //new users start with this rank.
int dbCleaning = 2;

//begin
public Plugin:myinfo =
{
	name = "SimpleCSGORanks",
	author = "Puppetmaster, Mehffort, Zipzip, Turtl, Fnz, Furreal",
	description = "SimpleCSGORanks Addon",
	version = PLUGIN_VERSION,
	url = "https://www.gamingzoneservers.com"
};

//sets a clients rank, checks if the client exists and then updates the rank, else it adds the user with a zero rank.
public void setRank(int steamId, int rank, int client) //done
{
	rankCache[client] = rank;
	rankCacheValidate[client] = 1; //revalidate once this is done

	//time
	new String:stime[65];
	IntToString(GetTime(),stime,sizeof(stime));
	
	new String:srank[65];
	new String:ssteamId[65];
	IntToString(rank,srank,sizeof(srank));
	IntToString(steamId,ssteamId,sizeof(ssteamId));
	new String:query[128];
	Format(query, sizeof(query), "UPDATE steam SET rank = %s, age = '%s' WHERE steamId = %s LIMIT 1", srank, stime, ssteamId); //limited
	if(printToServer == 1) PrintToServer("query: %s", query);	

	newUser(steamId); //adds the user if they are not in the database
	if (dbc == INVALID_HANDLE)
	{
		dbc = SQL_Connect(databaseName, false, errorc, sizeof(errorc));
		SQL_GetError(dbc, errorc, sizeof(errorc));
		if(printToServer == 1) PrintToServer("Failed to query (error: %s)", errorc);
	} 
	else {
		if (!SQL_FastQuery(dbc, query))
		{
			new String:error2[255]
			SQL_GetError(dbc, error2, sizeof(error2))
			if(printToServer == 1) PrintToServer("Failed to query (error: %s)", error2)
		}
	}
}

//adds the given number of points to the given user
public void addRank(int steamId, int points, int client)
{
	if(threadedCache == 0) setRank(steamId, (getRank(steamId) + points), client);
	else setRank(steamId, (getRankCached(steamId, 0, 0, 0) + points), client);
}

public void purgeOldUsers() 
{
	if( dbCleaning == 0 ) return;

	if (!SQL_FastQuery(dbc, "DELETE FROM steam WHERE rank = 100"))
	{
		new String:error5[255]
		SQL_GetError(dbc, error5, sizeof(error5))
		if(printToServer == 1) PrintToServer("Failed to query (error: %s)", error5)
	}
	if( dbCleaning == 1 ) return;

	//purges the database of all old users
	if (!SQL_FastQuery(dbc, "DELETE FROM steam WHERE age < ((SELECT UNIX_TIMESTAMP()) - (3600*24*60))"))
	{
		new String:error[255]
		SQL_GetError(dbc, error, sizeof(error))
		if(printToServer == 1) PrintToServer("Failed to query (error: %s)", error)
	}
	if (!SQL_FastQuery(dbc, "DELETE FROM steamname WHERE steamId NOT IN(SELECT steamId FROM steam)"))
	{
		new String:error3[255]
		SQL_GetError(dbc, error3, sizeof(error3))
		if(printToServer == 1) PrintToServer("Failed to query (error: %s)", error3)
	}
	if (!SQL_FastQuery(dbc, "DELETE FROM steam WHERE steamId NOT IN(SELECT steamId FROM steamname)"))
	{
		new String:error4[255]
		SQL_GetError(dbc, error4, sizeof(error4))
		if(printToServer == 1) PrintToServer("Failed to query (error: %s)", error4)
	}
	return;
}

//this gets run whenever a new user joins the server and is authenticated
public void newUser(int steamId) //done
{
	new String:ssteamId[65];
	new String:srank[65];
	new String:stime[65];
	IntToString(steamId,ssteamId,sizeof(ssteamId));
	IntToString(startRank,srank,sizeof(srank));
	IntToString(GetTime(),stime,sizeof(stime));
	new String:query[128];
	Format(query, sizeof(query), "INSERT INTO steam (steamId, rank, age) VALUES(%s,%s,%s)", ssteamId, srank, stime);

	if(printToServer == 1) PrintToServer("query: %s", query);
	
	if(dbc == INVALID_HANDLE){ 
		dbc = SQL_Connect(databaseName, false, errorc, sizeof(errorc));
		SQL_GetError(dbc, errorc, sizeof(errorc));
		if(printToServer == 1) PrintToServer("Failed to query (error: %s)", errorc);
	}
	
	if( immediateMode == 0 )
	{
		if (!SQL_FastQuery(dbc, query))
		{
			new String:error[255]
			SQL_GetError(dbc, error, sizeof(error))
			if(printToServer == 1) PrintToServer("Failed to query (error: %s)", error)
		}
	}
	else{
		SQL_TQuery(dbc, updateThread, query, 0);
	}

	return;
}

public int getSteamIdNumber(int client)
{
	if(!IsClientConnected(client)) return -1;
	decl String:steamId[64]; //defused the bomb
	GetClientAuthId(client, AuthId_Steam3, steamId, sizeof(steamId));
	ReplaceString(steamId, sizeof(steamId), "[U:1:", "", false);
	ReplaceString(steamId, sizeof(steamId), "[U:0:", "", false);
	ReplaceString(steamId, sizeof(steamId), "]", "", false);

	return StringToInt(steamId);
}

public OnClientPostAdminCheck(client){
	cacheCurrentClient = client; //attempt to cache a player immediately after they join
	CreateTimer(0.1, Timer_Cache);
	return;
}

public OnClientDisconnect(client){
	new maxclients = GetMaxClients();
	rankCacheValidate[1+cacheCurrentClient%maxclients] = 0;
	return;
}

//Threaded code

public updateThread(Handle:owner, Handle:HQuery, const String:error[], any:client)
{
	if(HQuery == INVALID_HANDLE){
		PrintToServer("Query failed! %s", error);
	}

	CloseHandle(HQuery); //make sure the handle is closed before we allow anything to happen
}

public queryCallback(Handle:owner, Handle:HQuery, const String:error[], any:client)
{
	if(HQuery == INVALID_HANDLE){
		PrintToServer("Query failed! %s", error);
	}
	else{
		new String:data[65]
		if(SQL_FetchRow(HQuery))
		{
			SQL_FetchString(HQuery, 0, data, sizeof(data));
			rankCache[client] = StringToInt(data);
			rankCacheValidate[client] = 1;  //Validate once the data is copied
		}
	}

	CloseHandle(HQuery); //make sure the handle is closed before we allow anything to happen
	dbLocked = 0; //unlock db after everything is done
}

public Action:Timer_Cache(Handle:timer)
{
	if(dbLocked == 1) return Plugin_Continue; //Only work while idle
	new maxclients = GetMaxClients();
	int skipped = 0;
	while(!IsClientInGame(1+cacheCurrentClient%maxclients) && skipped < maxclients)
	{
		skipped++;
		cacheCurrentClient++;
	}
	
	if( 1+cacheCurrentClient%maxclients  > maxclients) return Plugin_Continue;
	if(!IsClientInGame(1+cacheCurrentClient%maxclients)) return Plugin_Continue;
	if(IsFakeClient(1+cacheCurrentClient%maxclients)) return Plugin_Continue;
		
	if(printToServer == 1) PrintToServer("Client: %d", 1+cacheCurrentClient%maxclients);
	if(!IsClientInGame(1+cacheCurrentClient%maxclients)) {
		//if the spot is empty
		rankCacheValidate[1+cacheCurrentClient%maxclients] = 0; //invalidate the empty spot
		cacheCurrentClient++; //move on to the next spot
		return Plugin_Continue; //wait until the next call so we dont waste CPU cycles, after all this is a background task
	}
	
	decl String:steamId[64]; //defused the bomb
	GetClientAuthId(1+cacheCurrentClient%maxclients, AuthId_Steam3, steamId, sizeof(steamId));
	ReplaceString(steamId, sizeof(steamId), "[U:1:", "", false);
	ReplaceString(steamId, sizeof(steamId), "[U:0:", "", false);
	ReplaceString(steamId, sizeof(steamId), "]", "", false);

	new String:query[128];
	query = "SELECT rank FROM steam WHERE steamId = ";
	StrCat(steamId, sizeof(steamId), " LIMIT 1"); //limit optimisation
	StrCat(query, sizeof(query), steamId); //done

	if(dbt == INVALID_HANDLE){ 
		dbt = SQL_Connect(databaseName, false, errorc, sizeof(errorc));
		SQL_GetError(dbt, errorc, sizeof(errorc));
		if(printToServer == 1) PrintToServer("Failed to query (error: %s)", errorc);
	}
	dbLocked = 1; //Lock our own DB
	SQL_TQuery(dbt, queryCallback, query, 1+cacheCurrentClient%maxclients);

	cacheCurrentClient++;
	return Plugin_Continue;
}

public int getRankCached(int steamId, int usesClient, int client, int invalidateCache)
{
//needs all entered, if it fails to lookup from just client it falls back to the existing method
//getRankCached(id, usesclient, client, invalidateCache)
	int currentClient = -1;
	if(usesClient == 1) currentClient = client;
	else //Need to look up the client from the array
	{
		new maxclients = GetMaxClients()
		for(new i=1; i <= maxclients; i++)
		{
			if(getSteamIdNumber(i) == steamId) 
			{
				currentClient = i;//getSteamIdNumber(i);
				break;
			}
		}
	}
	if(printToServer == 1) PrintToServer("Current Client %d", currentClient);
	if(currentClient == -1) return getRank(steamId); //failed to look up client
	else if(rankCacheValidate[currentClient] == 0){
		return getRank(steamId);
	}
	else{
		if(invalidateCache == 1) rankCacheValidate[currentClient] = 0; //invalidate the cached copy, this flag is used when the query changes the rank
		if(printToServer == 1) PrintToServer("Returning cached rank %d", rankCache[currentClient]);
		return rankCache[currentClient]; //return the cached copy
	}
}
//end Threaded

//this is called whenever the rank command is used or another method needs to get a rank
public int getRank(int steamId)
{
	if(dbc == INVALID_HANDLE){ 
		dbc = SQL_Connect(databaseName, false, errorc, sizeof(errorc));
		SQL_GetError(dbc, errorc, sizeof(errorc));
		if(printToServer == 1) PrintToServer("Failed to query (error: %s)", errorc);
	}
	//return the users rank
	int rank;
	new String:ssteamId[65];
	IntToString(steamId,ssteamId,sizeof(ssteamId));
	new String:query[128];
	query = "SELECT rank FROM steam WHERE steamId = "
	StrCat(ssteamId, sizeof(ssteamId), " LIMIT 1"); //limit optimisation
	StrCat(query, sizeof(query), ssteamId); //done
	if(printToServer == 1) PrintToServer("query: %s", query);

	new Handle:query2 = SQL_Query(dbc, query);
	if (query2 == INVALID_HANDLE)
	{
		new String:error[255]
		SQL_GetError(dbc, error, sizeof(error))
		if(printToServer == 1) PrintToServer("Failed to query (error: %s)", error)
	} else {

		new String:name[65]
		while (SQL_FetchRow(query2))
		{
			SQL_FetchString(query2, 0, name, sizeof(name))
			if(printToServer == 1) PrintToServer("Getting rank of %s : %s", steamId, name)
			rank = StringToInt(name);
		}
	}
	CloseHandle(query2);
	return rank; 
}

//players position overall
public getRank2(int steamId, int i)
{
	if(dbc == INVALID_HANDLE){ 
		dbc = SQL_Connect(databaseName, false, errorc, sizeof(errorc));
		SQL_GetError(dbc, errorc, sizeof(errorc));
		if(printToServer == 1) PrintToServer("Failed to query (error: %s)", errorc);
	}
	newUser(steamId);
	new String:ssteamId[65];
	IntToString(steamId,ssteamId,sizeof(ssteamId));
	new String:query[400];
	Format(query, sizeof(query), "(SELECT CONCAT((SELECT count(steamId)+1 from steam where cast(rank as signed) > cast((SELECT rank from steam WHERE steamId =  %s LIMIT 1) as signed)),'/', (SELECT count(steamId) from steam)))", ssteamId); //limited
	if(printToServer == 1) PrintToServer("query: %s", query);
	new String:name[65];// = "h"
	new Handle:query2 = SQL_Query(dbc, query);
	if (query2 == INVALID_HANDLE)
	{
		new String:error[255];
		SQL_GetError(dbc, error, sizeof(error));
		if(printToServer == 1) PrintToServer("Failed to query (error: %s)", error);
	} 
	else {
		while (SQL_FetchRow(query2))
		{
			SQL_FetchString(query2, 0, name, sizeof(name))
			if(printToServer == 1) PrintToServer("Getting rank of %s : %s", steamId, name)
		}
	}
	CloseHandle(query2);
	decl String:name1[64];
	GetClientName(i, name1, sizeof(name1));
	if(printToServer == 1) PrintToServer("Player %s : %s", name1, name);
	ranksText2[i] = name;
}


//user one kills user two
public void userShot(int steamId1, int steamId2, int client, int client2) //done
{

	decl String:stime[65];
	decl String:ssteamId1[65];
	decl String:ssteamId2[65];
	decl String:query[440];
	decl String:query2[440];

	IntToString(GetTime(),stime,sizeof(stime));
	IntToString(steamId1,ssteamId1,sizeof(ssteamId1));
	IntToString(steamId2,ssteamId2,sizeof(ssteamId2));
	
	if(rankCacheValidate[client] == 1 && rankCacheValidate[client2] == 1){
		if(rankCache[client]+higherRankThreshold < rankCache[client2]){
			rankCache[client] += killPoints+higherRankFactor; 
			rankCache[client2] -= killPoints+1+higherRankFactor;
		}
		else{
			rankCache[client] += killPoints; 
			rankCache[client2] -= killPoints+1;
		}
	}
	else{
		rankCacheValidate[client] = 0;
		rankCacheValidate[client2] = 0;
	}


	Format(query, sizeof(query), "UPDATE steam SET steam.rank = (SELECT * FROM (SELECT CASE WHEN (SELECT cast(rank as decimal)+%d FROM steam WHERE steamId = %s LIMIT 1) < (SELECT cast(rank as decimal) FROM steam WHERE steamId = %s LIMIT 1) THEN rank+%d+%d ELSE rank+%d END FROM steam WHERE steamId = %s LIMIT 1) as b), steam.age = %s  WHERE steamId = %s LIMIT 1", higherRankThreshold, ssteamId1, ssteamId2, killPoints, higherRankFactor, killPoints, ssteamId1, stime, ssteamId1);
	Format(query2, sizeof(query2), "UPDATE steam SET steam.rank = (SELECT * FROM (SELECT CASE WHEN (SELECT cast(rank as decimal)+%d FROM steam WHERE steamId = %s LIMIT 1) < (SELECT cast(rank as decimal) FROM steam WHERE steamId = %s LIMIT 1) THEN rank-%d-%d ELSE rank-%d-1 END FROM steam WHERE steamId = %s LIMIT 1) as b), steam.age = %s  WHERE steamId = %s LIMIT 1", higherRankThreshold, ssteamId1, ssteamId2, killPoints, higherRankFactor, killPoints, ssteamId2, stime, ssteamId2);

	if(printToServer == 1) PrintToServer("query: %s", query);	
	if( immediateMode == 0 )
	{
		if (dbc == INVALID_HANDLE)
		{
			dbc = SQL_Connect(databaseName, false, errorc, sizeof(errorc));
			SQL_GetError(dbc, errorc, sizeof(errorc));
			if(printToServer == 1) PrintToServer("Failed to query (error: %s)", errorc);
		} else {
			if (!SQL_FastQuery(dbc, query))
			{
				new String:error2[255]
				SQL_GetError(dbc, error2, sizeof(error2))
				if(printToServer == 1) PrintToServer("Failed to query (error: %s)", error2)
			}
		}	
		
		if(printToServer == 1) PrintToServer("query: %s", query2);	
		
		if (dbc == INVALID_HANDLE)
		{
			dbc = SQL_Connect(databaseName, false, errorc, sizeof(errorc));
			SQL_GetError(dbc, errorc, sizeof(errorc));
			if(printToServer == 1) PrintToServer("Failed to query (error: %s)", errorc);
		} else {
			if (!SQL_FastQuery(dbc, query2))
			{
				new String:error3[255]
				SQL_GetError(dbc, error3, sizeof(error3))
				if(printToServer == 1) PrintToServer("Failed to query (error: %s)", error3)
			}
		}
	}
	else
	{
		//Threaded and immediate
		decl String:name1[64]; //shooter
		decl String:name2[64]; //got shot
		GetClientName(client, name1, sizeof(name1)); //shooter
		GetClientName(client2, name2, sizeof(name2)); //got shot
		CPrintToChatAll("{darkred}%s (%d) {green}killed %s (%d)", name1, getRankCached(StringToInt(ssteamId1), 1, client, 0), name2, getRankCached(StringToInt(ssteamId2), 1, client2, 0) );
		
		if (dbc == INVALID_HANDLE)
		{
			dbc = SQL_Connect(databaseName, false, errorc, sizeof(errorc));
			SQL_GetError(dbc, errorc, sizeof(errorc));
			if(printToServer == 1) PrintToServer("Failed to query (error: %s)", errorc);
		}
		newUser(steamId1);
		newUser(steamId2);
		SQL_TQuery(dbc, updateThread, query, 0);
		SQL_TQuery(dbc, updateThread, query2, 0);
		
	}
}

public bool dbWorks()
{
	//should return 1
	int isWorking = 0;
	new String:error2[255]
	//new Handle:db = SQL_DefConnect(error2, sizeof(error2))
	new Handle:db = SQL_Connect(databaseName, false, error2, sizeof(error2));
	if (db == INVALID_HANDLE)
	{
		if(printToServer == 1 || true) PrintToServer("Could not connect: %s", error2)
	}
	else
	{
		new Handle:query = SQL_Query(db, "SELECT count(*) FROM information_schema.tables WHERE table_name = 'steam'")
		if (query == INVALID_HANDLE)
		{
			new String:error[255]
			SQL_GetError(db, error, sizeof(error))
			if(printToServer == 1 || true) PrintToServer("Failed to query (error: %s)", error)
		} else {

			new String:name[65]
			while (SQL_FetchRow(query))
			{
				SQL_FetchString(query, 0, name, sizeof(name))
				PrintToServer("Database access check passed")
				isWorking = 1;//StringToInt(name);
			}
		}
		CloseHandle(query)
		
	}
	CloseHandle(db)
	if(isWorking > 0) return true;
	else return false;	
}

public void newDB()
{
	PrintToServer("Database setup has been called.")
	PrintToServer("If you get an error here you probably need to fix your database.")
	PrintToServer("Try changing your databases.cfg file");
	//add table to db
	new String:error2[255]
	//new Handle:db = SQL_DefConnect(error2, sizeof(error2))
	new Handle:db = SQL_Connect(databaseName, false, error2, sizeof(error2));

	//CREATE DATABASE IF NOT EXISTS steam
	if(printToServer == 1) PrintToServer("Adding database tables");
	if (!SQL_FastQuery(db, "CREATE TABLE `steam` (`steamId` char(65) CHARACTER SET utf8 COLLATE utf8_bin NOT NULL DEFAULT '', `rank` char(65) DEFAULT NULL, `age` char(65) DEFAULT NULL, PRIMARY KEY (`steamId`)) ENGINE=InnoDB DEFAULT CHARSET=latin1"))
	{
		new String:error[255]
		SQL_GetError(db, error, sizeof(error))
		if(printToServer == 1) PrintToServer("Failed to query (error: %s)", error) //always print now to easily allow users to determine early issues
	}
	if (!SQL_FastQuery(db, "CREATE TABLE `steamname` (`steamId` char(65) CHARACTER SET utf8 COLLATE utf8_bin NOT NULL DEFAULT '', `name` char(255) DEFAULT NULL, PRIMARY KEY (`steamId`)) ENGINE=InnoDB DEFAULT CHARSET=latin1;"))
	{
		new String:error3[255]
		SQL_GetError(db, error3, sizeof(error3))
		if(printToServer == 1) PrintToServer("Failed to query (error: %s)", error3)
	}
	CloseHandle(db)
	return;
}
//new
public void updateName(int steamId, char name[64])
{

	//id needs to be set to be a primary key
	//CREATE TABLE `steamname` ( steamId CHAR(65) CHARACTER SET utf8 COLLATE utf8_bin, name CHAR(255), PRIMARY KEY (steamId));
	new String:buffer[130];
	ReplaceString(name, sizeof(name), "select", "", false);
	ReplaceString(name, sizeof(name), "drop", "", false);
	ReplaceString(name, sizeof(name), "table", "", false);
	ReplaceString(name, sizeof(name), "insert", "", false);
	ReplaceString(name, sizeof(name), "where", "", false);
	ReplaceString(name, sizeof(name), "=", "", false);
	ReplaceString(name, sizeof(name), "use", "", false);
	ReplaceString(name, sizeof(name), "/", "", false);
	ReplaceString(name, sizeof(name), "|", "", false);
	ReplaceString(name, sizeof(name), "'", "", false);
	ReplaceString(name, sizeof(name), "\"", "", false);
	ReplaceString(name, sizeof(name), "/", "", false);
	ReplaceString(name, sizeof(name), "\\", "", false);
	ReplaceString(name, sizeof(name), ";", "", false);
	ReplaceString(name, sizeof(name), " OR ", "", false);
	ReplaceString(name, sizeof(name), "join", "", false);
	SQL_EscapeString(dbc, name, buffer, sizeof(buffer));
	new String:query[700]; //surely enough for a long name?
	Format(query, sizeof(query), "INSERT INTO steamname (steamId,name) VALUES ('%d','\%s\') ON DUPLICATE KEY UPDATE name='\%s\'", steamId, buffer, buffer); //name changed to buffer
	//make query
	if(printToServer == 1) PrintToServer("query: %s", query);

	//add user to db
	if(dbc == INVALID_HANDLE){ 
		dbc = SQL_Connect(databaseName, false, errorc, sizeof(errorc));
		SQL_GetError(dbc, errorc, sizeof(errorc));
		if(printToServer == 1) PrintToServer("Failed to query (error: %s)", errorc);
	}
	if (!SQL_FastQuery(dbc, query))
	{
		new String:error[255]
		SQL_GetError(dbc, error, sizeof(error))
		if(printToServer == 1) PrintToServer("Failed to query (error: %s)", error)
	}
}

//Copies out the array at the end of the round
public void copyOut()
{
	//check if DB is connected. If not reconnect.
	if(dbc == INVALID_HANDLE){ 
		dbc = SQL_Connect(databaseName, false, errorc, sizeof(errorc));
		SQL_GetError(dbc, errorc, sizeof(errorc));
		if(printToServer == 1) PrintToServer("Failed to query (error: %s)", errorc);
	}
	else {	
		decl String:steamId1[64]; //shooter
		decl String:steamId4[64]; //assister
		decl String:steamId2[64]; //got shot

		decl String:name1[64]; //shooter
		decl String:name4[64]; //assister
		decl String:name2[64]; //got shot

		int client;
		int client2;
		int client3;
		//new
		decl String:name3[64]; //defused the bomb
		decl String:steamId3[64]; //defused the bomb
		
		if(defuser != -1)
		{	
			if(IsClientConnected(defuser) && !IsFakeClient(defuser))
			{
				GetClientName(defuser, name3, sizeof(name3)); //got shot
				GetClientAuthId(defuser, AuthId_Steam3, steamId3, sizeof(steamId3));
				ReplaceString(steamId3, sizeof(steamId3), "[U:1:", "", false);
				ReplaceString(steamId3, sizeof(steamId3), "[U:0:", "", false);
				ReplaceString(steamId3, sizeof(steamId3), "]", "", false);
				PrintToChatAll("%s has defused the bomb! +5 rank!", name3);
				addRank(StringToInt(steamId3), 5, defuser);		
			}
			defuser = -1; //ready the variable for the next round
		}
		//new
		shotCountdown = 0
		if(printToServer == 1) PrintToServer("%d players were killed this round.", shotPlayers+1);
		while(shotCountdown <= shotPlayers )//while(shotPlayers > -1) //only happens if kills occur during a round, else it skips
		{
			client = shooter[shotCountdown];
			client2 = shot[shotCountdown];
			client3 = assister[shotCountdown];
			
			//check if they are connected
			if(IsClientConnected(client) && IsClientConnected(client2) && !IsFakeClient(client) && !IsFakeClient(client2))
			{
				


				if(printToServer == 1) PrintToServer("Killer:client:%d  Killed:client2:%d", client, client2);
				GetClientAuthId(client, AuthId_Steam3, steamId1, sizeof(steamId1));
				GetClientAuthId(client2, AuthId_Steam3, steamId2, sizeof(steamId2));
			
				ReplaceString(steamId1, sizeof(steamId1), "[U:1:", "", false);
				ReplaceString(steamId1, sizeof(steamId1), "[U:0:", "", false);
				ReplaceString(steamId1, sizeof(steamId1), "]", "", false);
				ReplaceString(steamId2, sizeof(steamId2), "[U:1:", "", false);
				ReplaceString(steamId2, sizeof(steamId2), "[U:0:", "", false);
				ReplaceString(steamId2, sizeof(steamId2), "]", "", false);
				if(printToServer == 1) PrintToServer("Killer:SteamId1:%s  Killed:SteamId2:%s", steamId1, steamId2);

				userShot(StringToInt(steamId1),StringToInt(steamId2), client, client2); //adds to first, takes from second

				//print out info
				GetClientName(client, name1, sizeof(name1)); //shooter
				GetClientName(client2, name2, sizeof(name2)); //got shot
				if(threadedCache == 0) CPrintToChatAll("{green}Kill #%d {darkred}%s (%d) {green}killed %s (%d)", (shotCountdown+1), name1, getRank(StringToInt(steamId1)), name2, getRank(StringToInt(steamId2)) );
				else CPrintToChatAll("{green}Kill #%d {darkred}%s (%d) {green}killed %s (%d)", (shotCountdown+1), name1, getRankCached(StringToInt(steamId1), 1, client, 0), name2, getRankCached(StringToInt(steamId2), 1, client2, 0) );			
				updateName(StringToInt(steamId1), name1); //make sure the users name is in the DB
				updateName(StringToInt(steamId2), name2);

				
				
			}
			else{
				CPrintToChatAll("{green}Kill #%d Player Left.", (shotCountdown+1) );
			}
			//Assister
			if(client3 > 0){
				if(IsClientConnected(client3) && !IsFakeClient(client3))
				{
					GetClientAuthId(client3, AuthId_Steam3, steamId4, sizeof(steamId4));
					ReplaceString(steamId4, sizeof(steamId4), "[U:1:", "", false);
					ReplaceString(steamId4, sizeof(steamId4), "[U:0:", "", false);
					ReplaceString(steamId4, sizeof(steamId4), "]", "", false);
					GetClientName(client3, name4, sizeof(name4));
					
					//add +2 for assist
					addRank(StringToInt(steamId4), 2, client3);
					
					if(threadedCache == 0) CPrintToChatAll("{darkred}%s (%d) Assisted this kill.", name4, getRank(StringToInt(steamId4)) );
					else CPrintToChatAll("{darkred}%s (%d) Assisted this kill.", name4,  getRankCached(StringToInt(steamId4), 1, client3, 0) );
				}
			}
			shotCountdown++;
		}
		shotPlayers = -1;
	}
	return;

}

//steam stuff
public int GetKillPointsConvar()
{
	char buffer[128]
	sm_simplecsgoranks_kill_points.GetString(buffer, 128)
	return (StringToInt(buffer) ? StringToInt(buffer) : 5 );
}
public int GetHigherRankAdditionalConvar()
{
	char buffer[128]
	sm_simplecsgoranks_higher_rank_additional.GetString(buffer, 128)
	return (StringToInt(buffer) ? StringToInt(buffer) : 5 );
}
public int GetHigherRankGapConvar()
{
	char buffer[128]
	sm_simplecsgoranks_higher_rank_gap.GetString(buffer, 128)
	return (StringToInt(buffer) ? StringToInt(buffer) : 200 );
}

public int GetDebugConvar()
{
	char buffer[128]
	sm_simplecsgoranks_debug.GetString(buffer, 128)
	return StringToInt(buffer);
}

public void GetDatabaseConvar()
{
	char buffer[128]
	sm_simplecsgoranks_database.GetString(buffer, 128)
	Format(databaseNew, sizeof(databaseNew), "%s", buffer);
}

public int GetCleaningConvar()
{
	char buffer[128]
	sm_simplecsgoranks_cleaning.GetString(buffer, 128)
	return StringToInt(buffer);
}


//called at start of plugin, sets everything up.
public OnPluginStart()
{
	sm_simplecsgoranks_kill_points = CreateConVar("sm_simplecsgoranks_kill_points", "5", "The number of points gained per kill")
	sm_simplecsgoranks_higher_rank_additional = CreateConVar("sm_simplecsgoranks_higher_rank_additional", "5", "Additional points gained when killing a higher ranked player.")
	sm_simplecsgoranks_higher_rank_gap = CreateConVar("sm_simplecsgoranks_higher_rank_gap", "500", "Difference between players ranks needed to consider one to be a higher ranked player.")

	sm_simplecsgoranks_database = CreateConVar("sm_simplecsgoranks_database", "default", "Allows changing of the database used from databases.cfg")
	sm_simplecsgoranks_cleaning = CreateConVar("sm_simplecsgoranks_cleaning", "2", "(0)Nothing. (1) Cleans the database. (2) Clears players who have no kills for more than two months.")
	sm_simplecsgoranks_debug = CreateConVar("sm_simplecsgoranks_debug", "0", "Enable or disable advanced error messages. (0 or 1)")

	int flags = sm_simplecsgoranks_database.Flags;
	flags &= ~FCVAR_PROTECTED;
	sm_simplecsgoranks_database.Flags = flags;
	sm_simplecsgoranks_cleaning.Flags = flags;
	sm_simplecsgoranks_debug.Flags = flags;
	sm_simplecsgoranks_kill_points.Flags = flags;
	sm_simplecsgoranks_higher_rank_additional.Flags = flags;
	sm_simplecsgoranks_higher_rank_gap.Flags = flags;
	
	if(GetHigherRankGapConvar()) higherRankThreshold = GetHigherRankGapConvar();
	if(GetHigherRankAdditionalConvar()) higherRankFactor = GetHigherRankAdditionalConvar();
	if(GetKillPointsConvar()) killPoints = GetKillPointsConvar();

	if(GetCleaningConvar()) dbCleaning = GetCleaningConvar();
	GetDatabaseConvar();
	if(strcmp(databaseNew, "", false) != 0) Format(databaseName, sizeof(databaseName), "%s", databaseNew);
	if(GetDebugConvar() == 1) printToServer = 1;
	else if(GetDebugConvar() == 0) printToServer = 0;
	PrintToServer("Database: \"%s\"  Got:\"%s\"", databaseName, databaseNew);
	
	ready = dbWorks(); //check if the database is set up. This does not ever function if sourcemod does not have mysql set up
	if(!ready){
		newDB(); //create a new table in the database if its not there
		ready = dbWorks(); //check again
	}
	//if the database doesnt work at all just disable the plugin
	 //try to clean the DB
	if(ready){
		HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre)
		HookEvent("round_prestart", Event_RoundEnd) //round_end
		HookEvent("round_poststart", Event_RoundStart) //new round
		HookEvent("bomb_defused", Event_BombDefused) //bomb gets defused
		PrintToServer("SimpleCSGORanks loaded. Database appears to be working");
		//dbc = SQL_DefConnect(errorc, sizeof(errorc)); //open the connection that will be used for the rest of the time
		dbc = SQL_Connect(databaseName, false, errorc, sizeof(errorc));
		databaseCheck = databaseName; //update it

		dbt = SQL_Connect(databaseName, false, errorc, sizeof(errorc));
		if(threadedWorker == 1) CreateTimer(2.0, Timer_Cache, _, TIMER_REPEAT); //begin caching worker
	}
	else{
		PrintToServer("Database Failure. Please make sure your MySQL database is correctly set up. If you believe it is please check the databases.cfg file, check the permissions and check the port."); //inform the user that its broken
	}
	if(ready) purgeOldUsers();
}

public Action:Event_BombDefused(Handle:event, const String:name[], bool:dontBroadcast) //new
{
	//add user to var
	defuser = GetClientOfUserId(GetEventInt(event, "userid"));
	return Plugin_Continue;
}

public Action:Event_RoundEnd(Handle:event, const String:name[], bool:dontBroadcast)
{
	
	GetDatabaseConvar();
	if(strcmp(databaseNew, "", false) != 0) Format(databaseName, sizeof(databaseName), "%s", databaseNew);
	if(printToServer == 1) PrintToServer("Database: \"%s\"  Got:\"%s\"", databaseName, databaseNew);
	if(strcmp(databaseCheck, databaseName, false) == 0) {
		//connect to the new convar.
		databaseCheck = databaseName;
		CloseHandle(dbc);
		dbc = SQL_Connect(databaseName, false, errorc, sizeof(errorc));
	}
	if(GetDebugConvar() == 1) printToServer = 1;
	else if(GetDebugConvar() == 0) printToServer = 0;
	
	if( immediateMode == 1 ) return Plugin_Continue;
	
	copyTime = GetEngineTime();
	while(shotPlayers > -1 || defuser != -1){
	shotPlayers--;
	if(shotPlayers > -1)CPrintToChatAll("{orange}----Round Over----");//PrintToChatAll("----Round Over----"); //PLUGIN_VERSION
	if(shotPlayers > -1)CPrintToChatAll("{green}SimpleCSGORanks v%s", PLUGIN_VERSION);
	if(shotPlayers > -1)CPrintToChatAll("{darkred}Calculating kills and ranks.");//PrintToChatAll("Pausing game: Calculating kills and ranks.");
	dbLocked = 1;
	copyOut();
	dbLocked = 0;
	
	CPrintToChatAll("{green} -- New Round --");
	}
	PrintToServer("Ranks calculation took %f", (GetEngineTime()-copyTime));
	return Plugin_Continue;
}
public Action:Event_RoundStart (Handle:event, const String:name[], bool:dontBroadcast){
	copyTime = GetEngineTime();
	getTop();
	updateRanksText(); //update at the start of the round so that new players get loaded
	PrintToServer("Update of !rank data took %f", (GetEngineTime()-copyTime));
	return Plugin_Continue;
}

//event is called every time a player dies.
public Action:Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{	
	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	int assist = GetClientOfUserId(GetEventInt(event, "assister"));
	int userId = GetClientOfUserId(GetEventInt(event, "userid"));
	if(!ready || IsFakeClient(attacker) || IsFakeClient(userId)) return Plugin_Continue;
	if(userId == 0 ||  attacker == 0) return Plugin_Continue; //fix
	if(shotPlayers < 0) shotPlayers = 0; //out of range check //This happens on the first kill of each round. If no kills occur in a round this prevents it from crashing. its essential
	
	if( immediateMode == 1 ) {
		
		userShot(getSteamIdNumber(attacker),getSteamIdNumber(userId), attacker, userId);
		return Plugin_Continue;
	}
	
	if(shotPlayers > 254) {
	dbLocked = 1;
	copyOut(); //if the buffer fills because you use a dumb addon that allows more than 32 players per team dont let it crash
	dbLocked = 0;
	}
	if(GetClientTeam(userId) != GetClientTeam(attacker))
	{	
		shooter[shotPlayers] = attacker; //the shooter
		assister[shotPlayers] = assist; //the assister
		shot[shotPlayers] = userId; //the guy who got shot
		if(printToServer == 1) PrintToServer("Added %d and %d to array.", shooter[shotPlayers], shot[shotPlayers]);
		shotPlayers++;
	}
	
	return Plugin_Continue;
}

public OnMapStart ()
{
	defuser = -1;
	updateRanksText();
	getTop();
}

public void getTop()
{
	if(dbc == INVALID_HANDLE){ 
		dbc = SQL_Connect(databaseName, false, errorc, sizeof(errorc));
		SQL_GetError(dbc, errorc, sizeof(errorc));
		if(printToServer == 1) PrintToServer("Failed to query (error: %s)", errorc);
	}

	new String:query[256];
	query = "select concat(\"{darkred}\", stn.name,\"{darkblue} - {green}\",a.rank) from (select * from steam order by cast(rank as decimal) desc limit 25) a join steamname stn on stn.steamId = a.steamId limit 25";

	if(printToServer == 1) PrintToServer("query: %s", query);

	new Handle:query2 = SQL_Query(dbc, query);
	if (query2 == INVALID_HANDLE)
	{
		new String:error[255]
		SQL_GetError(dbc, error, sizeof(error))
		if(printToServer == 1) PrintToServer("Failed to query (error: %s)", error)
	} else {

		new String:topTemp[128];
		int z = 0;
		//char sizeOfChar[1] = "a";
		while (SQL_FetchRow(query2) && z < 25)
		{
			SQL_FetchString(query2, 0, topTemp, sizeof(topTemp));
			if(printToServer == 1) PrintToServer("Getting top player:%s", topTemp);
			//Format(topRanks[z][], sizeof(sizeOfChar)*128, "%s", topTemp);
			strcopy(topRanks[z], 128, topTemp);
			z++;
		}
	
		
	}
	CloseHandle(query2);
}

//only allow when alive so that the variable has the correct information && IsPlayerAlive(i)
public updateRanksText(){
	new maxclients = GetMaxClients()
	new String:steamId1[64];
	for(new i=1; i <= maxclients; i++)
	{
		ranksText[i] = 0;
		if(IsClientInGame(i)) 
		{
			GetClientAuthId(i, AuthId_Steam3, steamId1, sizeof(steamId1));
			ReplaceString(steamId1, sizeof(steamId1), "[U:1:", "", false);
			ReplaceString(steamId1, sizeof(steamId1), "[U:0:", "", false);
			ReplaceString(steamId1, sizeof(steamId1), "]", "", false);
			if(threadedCache == 0) ranksText[i] = getRank(StringToInt(steamId1));
			else ranksText[i] = getRankCached(StringToInt(steamId1), 1, i, 0);
			getRank2(StringToInt(steamId1), i);
		}
	}
}

public Action OnClientSayCommand(int client, const char[] command, const char[] args) {
	new String:name[64];
	char ranksChatCommands[][] = { "!rank", "rank" };
	for (int i = 0; i < sizeof(ranksChatCommands); i++) {
	if (strcmp(args[0], ranksChatCommands[i], false) == 0) {
			GetClientName(client, name, sizeof(name));
			CPrintToChatAll("{green}%s's {darkred}Score: %d | Rank: %s", name, ranksText[client],ranksText2[client]); //Use this to change the !ranks text
		}
	}
	if((strcmp(args[0], "!top10", false) == 0) || (strcmp(args[0], "!top", false) == 0)){
		PrintToChat(client, "Top 10 Players");
		for(int z = 0; z < 10; z++){
			CPrintToChat(client,"%d: %s", z+1, topRanks[z]);
		}
	}
	if((strcmp(args[0], "!top25", false) == 0)){
		PrintToChat(client, "Top 25 Players");
		for(int z = 0; z < 25; z++){
			CPrintToChat(client,"%d: %s", z+1, topRanks[z]);
		}
	}
}

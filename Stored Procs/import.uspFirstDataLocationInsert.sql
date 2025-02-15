USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspFirstDataLocationInsert
	CreatedBy: Larry Dugger
	Description: This procedure will process all of the unprocessed records
		This will determine if the following exist(s) and will add or link the data
		Organization - Client, Location 
		Rule
		RiskControl
		Geo
		Channel

	Tables: [import].[File]
		,[import].[FirstDataLocation]

	Functions: [common].[ufnDownDimensionByOrgIdILTF]
		,[common].[ufnOrgClientAcronym]

	History:
		2018-02-02 - LBD - Created
		2018-03-08 - LBD - Correct second address call parameter @biAddressId....
		2018-03-12 - LBD - Modified, uses more efficient function
		2018-06-13 - LBD - Modified, adjusted call to 'RiskLevel' to 'RiskControl'
			for orgtype
		2018-09-04 - LBD - Modified, discovered the rule parent was being assigned.
		2020-06-18 - LBD - Added Lat and Long support
		2021-01-14 - CBS - Added [common].[ufnOrgClientAcronym](OrgName, ' ') to assign
			next available ExternalCode
		2021-05-10 - CBS - Backed out the update from 2021-01-14.  It's creating duplicate
			Client Org records.  I haven't had time to troubleshoot where it's broken yet
		2025-01-14 - LXK - Replaced table variables with local temp tables
*****************************************************************************************/
ALTER   PROCEDURE [import].[uspFirstDataLocationInsert]
	@piFileId INT
AS
BEGIN
	SET NOCOUNT ON;
	drop table if exists #FirstDataLocationInsertDol
	create table #FirstDataLocationInsertDol(
		 LevelId int
		,ParentId int
		,OrgId int
		,OrgCode nvarchar(25)
		,OrgName nvarchar(50)
		,ExternalCode nvarchar(50)
		,OrgDescr nvarchar(255)
		,TypeId	int
		,[Type]	nvarchar(25)
		,StatusFlag	int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
	);
	drop table if exists #FirstDataLocationInsert
	create table #FirstDataLocationInsert(
		 Id int
		,FileId int
		,RecordCreateDate nvarchar(50)
		,MMID nvarchar(50)
		,MMIDName nvarchar(50)
		,SubscriberName nvarchar(50)
		,TeleCheckSubscriberID nvarchar(50)
		,SubscriberAddress1 nvarchar(50)
		,SubscriberAddress2 nvarchar(50)
		,City nvarchar(50)
		,[State] nvarchar(50)
		,Zip nvarchar(50)
		,ProductStat_Ind nvarchar(50)
		,SIC_Description nvarchar(50) 
		,ClientOrgId int
		,LocationOrgId int
		,RuleOrgId int
		,RiskControlOrgId int
		,GeoOrgId int
		,ChannelOrgId int
		,Latitude float
		,Longitude float
		,Processed int
	);

 	DECLARE @iId int 
		,@iPartnerOrgId int
		,@iClientOrgId int
		,@iLocationOrgId int
		,@iTellerChannelOrgId int
		,@iRiskControlOrgId int
		,@iRuleOrgId int
		,@iDimensionId int
		,@iOrgParentId int
		,@iOrgChildId int
		,@iOrgXrefId int
		,@iClientTypeId int = [common].[ufnOrgType]('Client') 
		,@iLocationTypeId int = [common].[ufnOrgType]('Location')	
		,@iZipCodeTypeId int = [common].[ufnOrgType]('ZipCode')	
		,@iChannelTypeId int = [common].[ufnOrgType]('Channel')
		,@iRiskLevelTypeId  int = [common].[ufnOrgType]('RiskControl')  
		,@iRuleTypeId  int = [common].[ufnOrgType]('Rule')  
		,@iOrganizationDimensionId int = [common].[ufnDimension]('Organization') 
		,@iRuleDimensionId int = [common].[ufnDimension]('Rule') 
		,@iGeoDimensionId int = [common].[ufnDimension]('Geo')	
		,@iChannelDimensionId int = [common].[ufnDimension]('Channel')
		,@iRiskControlDimensionId  int = [common].[ufnDimension]('RiskControl') 
		,@iOrgDimensionId int = [common].[ufnDimension]('Organization')
		,@nvUserName nvarchar(100) = 'Import FirstData Locations'
		,@nvRuleParentName nvarchar(50) = 'First Data Casino Rules 1'
		,@nvOrgCode nvarchar(25)  
		,@nvOrgName nvarchar(50)
		,@nvAcronym nvarchar(50) 
		,@nvExternalCode nvarchar(50)
		,@biAddressId bigint
		,@nvAddress1 nvarchar(150)
		,@nvAddress2 nvarchar(150)
		,@nvCity nvarchar(100)
		,@nvStateCode nvarchar(25)
		,@ncZipCode nchar(5)
		,@iStateId int
		,@iStatusFlag int = 1
		,@iOrgAddressXrefId int
		,@fLatitude float
		,@fLongitude float
		,@iErrorDetailId int
		,@iCurrentTransactionLevel int
		,@sSchemaName nvarchar(128) = N'import';
	--Partner
	SELECT @iPartnerOrgId = OrgId 
	FROM [organization].[Org]
	WHERE [Name] = 'First Data';
	--Channel
	SELECT @iTellerChannelOrgId = OrgId
	FROM [organization].[Org]
	WHERE OrgTypeId = @iChannelTypeId
		AND Name = 'Teller'
	--RiskControl
	SELECT @iRiskControlOrgId = OrgId
	FROM [organization].[Org]
	WHERE OrgTypeId = @iRiskLevelTypeId
		AND Name = 'NewClient';
	--Rule
	SELECT @iRuleOrgId = OrgId
	FROM [organization].[Org]
	WHERE OrgTypeId = @iRuleTypeId
		AND Name = @nvRuleParentName;

	INSERT INTO #FirstDataLocationInsertDol(LevelId,ParentId,OrgId,OrgName,ExternalCode,TypeId,[Type],StatusFlag,DateActivated)
	SELECT LevelId,ParentId,OrgId,OrgName,ExternalCode,TypeId,[Type],StatusFlag,DateActivated
	FROM [common].[ufnDownDimensionByOrgIdILTF](@iPartnerOrgId,@iOrgDimensionId);

	INSERT INTO #FirstDataLocationInsert([Id], [FileId], [RecordCreateDate], [MMID], [MMIDName], [SubscriberName]
		,[TeleCheckSubscriberID], [SubscriberAddress1], [SubscriberAddress2], [City], [State], [Zip]
		,[ProductStat_Ind], [SIC_Description], [ClientOrgId], [LocationOrgId], [RuleOrgId]
		,[RiskControlOrgId], [GeoOrgId], [ChannelOrgId], [Latitude], [Longitude], [Processed])
	SELECT [Id], [FileId], [RecordCreateDate], [MMID], [MMIDName], [SubscriberName]
		,[TeleCheckSubscriberID], [SubscriberAddress1], [SubscriberAddress2], [City], [State], [Zip]
		,[ProductStat_Ind], [SIC_Description], 0, 0
		,TRY_CONVERT(FLOAT,[Latitude]) as Latitude, TRY_CONVERT(FLOAT,[Longitude]) as Longitude, 0
		,0, 0, 0, 0
	FROM [import].[FirstDataLocation]
	WHERE FileId = @piFileId 
		AND Processed = 0;

	--Client Already Exist
	UPDATE fdl
		SET ClientOrgId = d.OrgId
	FROM #FirstDataLocationInsert fdl
	INNER JOIN #FirstDataLocationInsertDol d ON fdl.SubscriberName = d.OrgName
							AND d.[Type] = 'Client';
	--Location Already Exist
	UPDATE fdl
		SET LocationOrgId = d.OrgId
	FROM #FirstDataLocationInsert fdl
	INNER JOIN #FirstDataLocationInsertDol d ON (fdl.SubscriberName+' Loc '+fdl.TeleCheckSubscriberID) = d.OrgName
							AND d.[Type] = 'Location';
	--Set the others to what works for FirstData
	UPDATE fdl
		SET RuleOrgId =	@iRuleOrgId
		,RiskControlOrgId =	@iRiskControlOrgId
		,GeoOrgId =	o.OrgId
		,ChannelOrgId = @iTellerChannelOrgId
	FROM #FirstDataLocationInsert fdl
	LEFT OUTER JOIN [organization].[Org] o on fdl.Zip = o.[Name]
									AND o.OrgTypeId = @iZipCodeTypeId

	--Add in acrynonym check if new client, check relationships existence

	--Create new 'org' ids first
	--Insert New Clients
	DECLARE csr_Client CURSOR FOR
	SELECT Id, SubscriberName,[import].[ufnAcronym](SubscriberName,' ')+'Clnt' as Acronym --2021-01-14,2021-05-10
	--SELECT Id, SubscriberName,[common].[ufnOrgClientAcronym](SubscriberName, ' ') as Acronym --2021-01-14,2021-05-10
		,SubscriberAddress1, SubscriberAddress2, City, [State], Zip, ISNULL(Latitude,-1), ISNULL(Longitude,-1)
	FROM #FirstDataLocationInsert
	WHERE ClientOrgId = 0;
	OPEN csr_Client;
	FETCH csr_Client INTO @iId, @nvOrgName, @nvAcronym, @nvAddress1, @nvAddress2, @nvCity, @nvStateCode, @ncZipCode, @fLatitude, @fLongitude;
	WHILE @@FETCH_STATUS = 0
	BEGIN
		set @iClientOrgId = null;
		set @biAddressId= null;	
		set @iOrgAddressXrefId= null;
		EXECUTE [organization].[uspOrgInsertOut] @piOrgTypeId=@iClientTypeId, @pnvCode=@nvAcronym, @pnvName=@nvOrgName, @pnvDescr=@nvOrgName, @pnvExternalCode=@nvAcronym, @piStatusFlag=@iStatusFlag, @pnvUserName=@nvUserName, @piOrgId=@iClientOrgId output;
		IF @iClientOrgId > 0
		BEGIN	
			IF NOT EXISTS (SELECT 'X' FROM [organization].[OrgAddressXref] 
					WHERE OrgId = @iClientOrgId AND StatusFlag = 1) --This Org doesn't have an active address
			BEGIN						  
				EXECUTE [common].[uspAddressInsertOut] @pnvAddress1=@nvAddress1, @pnvAddress2=@nvAddress2, @pnvCity=@nvCity, @pnvStateAbbv=@nvStateCode, @pnvZipCode=@ncZipCode, @pnvCountry='USA', @pfLatitude=@fLatitude, @pfLongitude=@fLongitude, @piStatusFlag=@iStatusFlag, @pnvUserName=@nvUserName, @pbiAddressId=@biAddressId output;

				IF @biAddressId > 0
					EXECUTE [organization].[uspOrgAddressXrefInsertOut] @piOrgId=@iClientOrgId, @pbiAddressId=@biAddressId, @pfLatitude=@fLatitude, @pfLongitude=@fLongitude, @piStatusFlag=@iStatusFlag, @pnvUserName=@nvUserName, @piOrgAddressXrefId = @iOrgAddressXrefId output;
			END
			UPDATE fdl
				SET ClientOrgId = @iClientOrgId
			FROM #FirstDataLocationInsert fdl
			WHERE fdl.Id = @iId;
		END
 	
		FETCH csr_Client INTO @iId, @nvOrgName, @nvAcronym, @nvAddress1, @nvAddress2, @nvCity, @nvStateCode, @ncZipCode, @fLatitude, @fLongitude;
	END 
	CLOSE csr_Client;
	DEALLOCATE csr_Client;

	--select 'Post Client' as here, * from #FirstDataLocationInsert

	--Insert New Locations
	DECLARE csr_Location CURSOR FOR
	SELECT Id, SubscriberName+' Loc '+TeleCheckSubscriberID as [Name],'TL'+TeleCheckSubscriberID as Code, TeleCheckSubscriberID AS ExternalCode
		,SubscriberAddress1, SubscriberAddress2, City, [State], Zip, ISNULL(Latitude,-1), ISNULL(Longitude,-1)
	FROM #FirstDataLocationInsert
	WHERE LocationOrgId = 0;
	OPEN csr_Location
	FETCH csr_Location INTO @iId, @nvOrgName, @nvOrgCode, @nvExternalCode, @nvAddress1, @nvAddress2, @nvCity, @nvStateCode, @ncZipCode, @fLatitude, @fLongitude;
	WHILE @@FETCH_STATUS = 0
	BEGIN	   
		set @iLocationOrgId = null;
		set @biAddressId= null;	
		set @iOrgAddressXrefId= null;
		EXECUTE [organization].[uspOrgInsertOut] @piOrgTypeId=@iLocationTypeId, @pnvCode=@nvOrgCode, @pnvName=@nvOrgName, @pnvDescr=@nvOrgName, @pnvExternalCode=@nvExternalCode, @piStatusFlag=@iStatusFlag, @pnvUserName=@nvUserName, @piOrgId=@iLocationOrgId output;
		IF @iLocationOrgId > 0
		BEGIN							  
			IF NOT EXISTS (SELECT 'X' FROM [organization].[OrgAddressXref] 
					WHERE OrgId = @iLocationOrgId AND StatusFlag = 1) --This Org doesn't have an active address
			BEGIN						  
				EXECUTE [common].[uspAddressInsertOut] @pnvAddress1=@nvAddress1, @pnvAddress2=@nvAddress2, @pnvCity=@nvCity, @pnvStateAbbv=@nvStateCode, @pnvZipCode=@ncZipCode, @pnvCountry='USA', @pfLatitude=@fLatitude, @pfLongitude=@fLongitude, @piStatusFlag=@iStatusFlag, @pnvUserName=@nvUserName, @pbiAddressId=@biAddressId output;

				IF @biAddressId > 0
					EXECUTE [organization].[uspOrgAddressXrefInsertOut] @piOrgId=@iLocationOrgId, @pbiAddressId=@biAddressId, @pfLatitude=@fLatitude, @pfLongitude=@fLongitude, @piStatusFlag=@iStatusFlag, @pnvUserName=@nvUserName, @piOrgAddressXrefId = @iOrgAddressXrefId output;
			END
			UPDATE fdl
				SET LocationOrgId = @iLocationOrgId
			FROM #FirstDataLocationInsert fdl
			WHERE Id = @iId;
		END

		FETCH csr_Location INTO @iId, @nvOrgName, @nvOrgCode, @nvExternalCode, @nvAddress1, @nvAddress2, @nvCity, @nvStateCode, @ncZipCode, @fLatitude, @fLongitude;
	END
	CLOSE csr_Location;
	DEALLOCATE csr_Location; 

	--select 'Post Location' as here, * from #FirstDataLocationInsert

	--Build org CrossReferences
 	DECLARE csr_OrgXref CURSOR FOR
	--client to partner
	SELECT Id
		,@iOrganizationDimensionId as DimensionId
		,@iPartnerOrgId as OrgParentId
		,ClientOrgId as OrgChildId
	FROM #FirstDataLocationInsert
	UNION ALL--loc to client
	SELECT Id
		,@iOrganizationDimensionId as DimensionId
		,ClientOrgId as OrgParentId
		,LocationOrgId as OrgChildId
	FROM #FirstDataLocationInsert
	UNION ALL--loc to rule
 	SELECT Id
		,@iRuleDimensionId as DimensionId
		,RuleOrgId as OrgParentId
		,LocationOrgId as OrgChildId
	FROM #FirstDataLocationInsert
	UNION ALL--loc to risk
 	SELECT Id
		,@iRiskControlDimensionId as DimensionId
		,RiskControlOrgId as OrgParentId
		,LocationOrgId as OrgChildId
	FROM #FirstDataLocationInsert
	UNION ALL--loc to geo
 	SELECT Id
		,@iGeoDimensionId as DimensionId
		,GeoOrgId as OrgParentId
		,LocationOrgId as OrgChildId
	FROM #FirstDataLocationInsert
	UNION ALL--loc to channel
 	SELECT Id
		,@iChannelDimensionId as DimensionId
		,ChannelOrgId as OrgParentId
		,LocationOrgId as OrgChildId
	FROM #FirstDataLocationInsert;
 	OPEN csr_OrgXref
	FETCH csr_OrgXref INTO @iId, @iDimensionId, @iOrgParentId, @iOrgChildId;
	WHILE @@FETCH_STATUS = 0
	BEGIN
		SET @iOrgXrefId = NULL;					  
		EXECUTE [organization].[uspOrgXrefInsertOut] 
			 @piDimensionid = @iDimensionId
			,@piOrgParentId	= @iOrgParentId
			,@piOrgChildId = @iOrgChildId
			,@piStatusFlag = @iStatusFlag
			,@pnvUserName = @nvUserName
			,@piOrgXrefId = @iOrgXrefId OUTPUT;
		IF @iOrgXrefId > 0
			UPDATE #FirstDataLocationInsert
				SET Processed += 1
			WHERE Id = @iId;
 		FETCH csr_OrgXref INTO @iId, @iDimensionId, @iOrgParentId, @iOrgChildId;
	END
	CLOSE csr_OrgXref
	DEALLOCATE csr_OrgXref

	--select 'Post xref' as here,* from #FirstDataLocationInsert;

	UPDATE fdl
		SET Processed = 1
	FROM [import].[FirstDataLocation] fdl
	INNER JOIN #FirstDataLocationInsert fdl2 on fdl.Id = fdl2.Id
	WHERE fdl2.Processed = 6 --means we added all orgxrefs successfully
		AND ClientOrgId > 0	 --client exists
		AND LocationOrgId > 0; --location exists

END

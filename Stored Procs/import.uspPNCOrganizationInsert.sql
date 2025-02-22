USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/****************************************************************************************
	Name: uspPNCOrganizationInsert
	CreatedBy: Larry Dugger
	Description: This procedure will insert a new records into
	Tables: [import].[BulkOrganization]
		,[import].[PNCOrganization]

	Functions: [import].[uspProcessPNCOrganization]	   
				--bounces off [import].[ExpressFundsList] to limint ATMs imported
		,[common].[ufnUpDimensionByOrgIdILTF]

	History:
		2018-02-08 - LBD - Created, weird....
		2018-03-21 - LBD - Modified, uses more efficient function
*****************************************************************************************/
ALTER PROCEDURE [import].[uspPNCOrganizationInsert](
	 @pbiFileId BIGINT	= 0
)
AS
BEGIN
	SET NOCOUNT ON;
	
	drop table if exists #PNCOrganizationInsertBulk
	create table #PNCOrganizationInsertBulk(
		BulkExceptionId bigint
	);
	drop table if exists #PNCOrganizationInsertDol
	create table #PNCOrganizationInsertDol(
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
	drop table if exists #PNCOrganizationInsert
	create table #PNCOrganizationInsert(
		 BulkOrganizationId bigint primary key
		,ParentCode nvarchar(25)
		,OnPremises bit
		,OrgTypeId int
		,Code nvarchar(25)
		,[Name] nvarchar(50)
		,Descr nvarchar(255)
		,ExternalCode nvarchar(50)
		,Address1 nvarchar(150)
		,Address2 nvarchar(150)
		,City nvarchar(100)
		,StateCode nvarchar(25)
		,ZipCode nchar(5)
		,ZipCodeLast4 nchar(4)
		,Country nvarchar(50)
		,Latitude float
		,Longitude float
		,DateInService date
		,DateOutofService date
		,StatusFlag int
		,Processed bit
		,ClientOrgId int
		,LocationOrgId int
		,SubLocationOrgId int
		,RiskControlOrgId int
		,GeoOrgId int
		,ChannelOrgId int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
	);
	DECLARE @biBulkOrganizationId bigint 
		,@iPartnerOrgId int
		,@iPNCClientOrgId int
		,@iOPAtmLocationOrgId int
		,@iLocationOrgId int 
		,@iSubLocationOrgId int
		,@iAtmChannelOrgId int
		,@iRiskControlOrgId int
		,@iRuleOrgId int
		,@iDimensionId int
		,@iOrgParentId int
		,@iOrgChildId int
		,@iOrgXrefId int 
		,@iPartnerTypeId int = [common].[ufnOrgType]('Partner')
		,@iClientTypeId int = [common].[ufnOrgType]('Client')
		,@iLocationTypeId int = [common].[ufnOrgType]('Location')
		,@iSubLocationTypeId int = [common].[ufnOrgType]('SubLocation')	
		,@iZipCodeTypeId int = [common].[ufnOrgType]('ZipCode')	
		,@iChannelTypeId int = [common].[ufnOrgType]('Channel')
		,@iRiskLevelTypeId  int = [common].[ufnOrgType]('RiskControl')  
		,@iOrganizationDimensionId int = [common].[ufnDimension]('Organization') 
		,@iRuleDimensionId int = [common].[ufnDimension]('Rule') 
		,@iGeoDimensionId int = [common].[ufnDimension]('Geo')	
		,@iRiskControlDimensionId int = [common].[ufnDimension]('RiskControl') 
		,@iChannelDimensionId int = [common].[ufnDimension]('Channel') 
		,@iAtmChannelId	int = [common].[ufnChannel]('ATM') 
		,@iOrgDimensionId int = [common].[ufnDimension]('Organization')
		,@nvUserName nvarchar(100) = 'Import PNC ATMs'
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
		,@iStateCode int
		,@iStatusFlag int = 1
		,@iOrgAddressXrefId int
		,@iErrorDetailId int
		,@iCurrentTransactionLevel int
		,@sSchemaName nvarchar(128) = N'import';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;

	--Partner
	SELECT @iPartnerOrgId = OrgId 
	FROM [organization].[Org]
	WHERE [Name] = 'Fiserv'
		AND OrgTypeId = @iPartnerTypeId;
	--PNC
	SELECT @iPNCClientOrgId = OrgId 
	FROM [organization].[Org]
	WHERE [Name] = 'PNC Bank'
		AND OrgTypeId = @iClientTypeId;
	--PNC
	SELECT @iOPAtmLocationOrgId = OrgId 
	FROM [organization].[Org]
	WHERE [Name] = 'PNC OPATMs'
		AND OrgTypeId = @iLocationTypeId;
	--Channel
	SELECT @iAtmChannelOrgId = OrgId
	FROM [organization].[Org]
	WHERE OrgTypeId = @iChannelTypeId
		AND [Name] = 'ATM'
	--RiskControl
	SELECT @iRiskControlOrgId = OrgId
	FROM [organization].[Org]
	WHERE OrgTypeId = @iRiskLevelTypeId
		AND [Name] = 'PNC RC';

	INSERT INTO #PNCOrganizationInsertDol(LevelId,ParentId,OrgId,OrgName,ExternalCode,TypeId,[Type],StatusFlag,DateActivated)
	SELECT LevelId,ParentId,OrgId,OrgName,ExternalCode,TypeId,[Type],StatusFlag,DateActivated
	FROM [common].[ufnDownDimensionByOrgIdILTF](@iPartnerOrgId,@iOrgDimensionId);	--RiskControl

	INSERT INTO #PNCOrganizationInsert( BulkOrganizationId, ParentCode, OnPremises, OrgTypeId, Code, [Name], Descr
		,ExternalCode, Address1, Address2, City, StateCode, ZipCode, ZipCodeLast4, Country, Latitude, Longitude
		,DateInService, DateOutofService, Processed, DateActivated, UserName, ClientOrgId, LocationOrgId, SubLocationOrgId)
	SELECT BulkOrganizationId, 
		CASE WHEN OnPremises = 0 THEN 'PNC'
			WHEN OnPremises = 1 THEN 'OPATMs'
		END as ParentCode
		, OnPremises
		,CASE WHEN OnPremises = 0 THEN @iLocationTypeId 
			WHEN OnPremises = 1 THEN @iSubLocationTypeId
		 END as OrgTypeId, Code, [Name], Descr, ExternalCode, Address1, Address2
		,City, StateCode, ZipCode, ZipCodeLast4, Country, Latitude, Longitude
		,CASE WHEN DateInService = '1900-01-01' THEN NULL ELSE DateInService END
		,CASE WHEN DateOutofService = '1900-01-01' THEN NULL ELSE DateOutofService END
		,0, SYSDATETIME(), bo.UserName,0,0,0
	FROM [import].[BulkOrganization] bo
	CROSS APPLY [import].[ufnPNCOrganizationList](bo.FileRow,',',1) pel
	WHERE bo.FileId = @pbiFileId	--just the file indicated
		AND bo.RowType = 'A'		--just pickup the exception rows, no headers or tails
		AND bo.Processed = 0;		--only those we haven't inserted

	INSERT INTO [import].[PNCOrganization]([BulkOrganizationId], [ParentCode], [OnPremises], [OrgTypeId], [Code], [Name], [Descr], [ExternalCode], [Address1], [Address2], [City]
		,[StateCode], [ZipCode], [ZipCodeLast4], [Country], [Latitude], [Longitude], [DateInService], [DateOutofService], [StatusFlag], [Processed], [DateActivated], [UserName])
	SELECT [BulkOrganizationId], [ParentCode], [OnPremises], [OrgTypeId], [Code], [Name], [Descr], [ExternalCode], [Address1], [Address2], [City]
		,[StateCode], [ZipCode], [ZipCodeLast4], [Country], [Latitude], [Longitude], [DateInService], [DateOutofService], [StatusFlag], [Processed], [DateActivated], [UserName]
	FROM #PNCOrganizationInsert;

	IF EXISTS (SELECT 'X' FROM #PNCOrganizationInsert)
	BEGIN
		--Client Already Exist
		UPDATE o
			SET ClientOrgId = @iPNCClientOrgId
		FROM #PNCOrganizationInsert o;
		--Location Already Exist
		UPDATE o
			SET LocationOrgId = d.OrgId
		FROM #PNCOrganizationInsert o
		INNER JOIN #PNCOrganizationInsertDol d ON (o.[Name] = d.OrgName
									OR o.ParentCode = d.OrgCode)
								AND d.[Type] = 'Location';
		--SubLocation Already Exist
		UPDATE o
			SET SubLocationOrgId = d.OrgId
		FROM #PNCOrganizationInsert o
		INNER JOIN #PNCOrganizationInsertDol d ON o.[Name] = d.OrgName
								AND d.[Type] = 'SubLocation';
		--Set the others to what works for PNC
		UPDATE o
			SET RiskControlOrgId = @iRiskControlOrgId
			,GeoOrgId =	o1.OrgId
			,ChannelOrgId = @iATMChannelOrgId
		FROM #PNCOrganizationInsert o
		LEFT OUTER JOIN [organization].[Org] o1 on o.ZipCode = o1.[Name]
										AND o1.OrgTypeId = @iZipCodeTypeId;		
	
	--SELECT * FROM #PNCOrganizationInsert;
  
 	--Create new 'org' ids first
	--Insert New Locations
	DECLARE csr_Location CURSOR FOR
	SELECT BulkOrganizationId, [Name], Code, ExternalCode, Address1, Address2, City, StateCode, ZipCode
	FROM #PNCOrganizationInsert
	WHERE LocationOrgId = 0
		AND OrgTypeId = @iLocationTypeId;
	OPEN csr_Location
	FETCH csr_Location INTO @biBulkOrganizationId, @nvOrgName, @nvOrgCode, @nvExternalCode, @nvAddress1, @nvAddress2, @nvCity, @nvStateCode, @ncZipCode;
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
				EXECUTE [common].[uspAddressInsertOut] @pnvAddress1=@nvAddress1, @pnvAddress2=@nvAddress2, @pnvCity=@nvCity, @pnvStateAbbv=@nvStateCode, @pnvZipCode=@ncZipCode, @pnvCountry=null, @pfLatitude=-1, @pfLongitude=-1, @piStatusFlag=@iStatusFlag, @pnvUserName=@nvUserName, @pbiAddressId=@biAddressId output;

				IF @biAddressId > 0
					EXECUTE [organization].[uspOrgAddressXrefInsertOut] @piOrgId=@iLocationOrgId, @pbiAddressId=@biAddressId, @pfLatitude=-1, @pfLongitude=-1, @piStatusFlag=@iStatusFlag, @pnvUserName=@nvUserName, @piOrgAddressXrefId = @iOrgAddressXrefId output;
			END
			UPDATE o
				SET LocationOrgId = @iLocationOrgId
			FROM #PNCOrganizationInsert o
			WHERE BulkOrganizationId = @biBulkOrganizationId;
		END

		FETCH csr_Location INTO @biBulkOrganizationId, @nvOrgName, @nvOrgCode, @nvExternalCode, @nvAddress1, @nvAddress2, @nvCity, @nvStateCode, @ncZipCode
	END
	CLOSE csr_Location;
	DEALLOCATE csr_Location; 

	--SELECT * FROM #PNCOrganizationInsert;

	--Insert new SubLocations
 	DECLARE csr_subLocation CURSOR FOR
	SELECT BulkOrganizationId, [Name], Code, ExternalCode, Address1, Address2, City, StateCode, ZipCode
	FROM #PNCOrganizationInsert
	WHERE SubLocationOrgId = 0
		AND OrgTypeId = @iSubLocationTypeId;
	OPEN csr_subLocation
	FETCH csr_subLocation INTO @biBulkOrganizationId, @nvOrgName, @nvOrgCode, @nvExternalCode, @nvAddress1, @nvAddress2, @nvCity, @nvStateCode, @ncZipCode;
	WHILE @@FETCH_STATUS = 0
	BEGIN	   
		set @iSubLocationOrgId = null;
		set @biAddressId= null;	
		set @iOrgAddressXrefId= null;
		EXECUTE [organization].[uspOrgInsertOut] @piOrgTypeId=@iSubLocationTypeId, @pnvCode=@nvOrgCode, @pnvName=@nvOrgName, @pnvDescr=@nvOrgName, @pnvExternalCode=@nvExternalCode, @piStatusFlag=@iStatusFlag, @pnvUserName=@nvUserName, @piOrgId=@iSubLocationOrgId output;
		IF @iLocationOrgId > 0
		BEGIN							  
			IF NOT EXISTS (SELECT 'X' FROM [organization].[OrgAddressXref] 
					WHERE OrgId = @iSubLocationOrgId AND StatusFlag = 1) --This Org doesn't have an active address
			BEGIN						  
				EXECUTE [common].[uspAddressInsertOut] @pnvAddress1=@nvAddress1, @pnvAddress2=@nvAddress2, @pnvCity=@nvCity, @pnvStateAbbv=@nvStateCode, @pnvZipCode=@ncZipCode, @pnvCountry=null, @pfLatitude=-1, @pfLongitude=-1, @piStatusFlag=@iStatusFlag, @pnvUserName=@nvUserName, @pbiAddressId=@biAddressId output;

				IF @biAddressId > 0
					EXECUTE [organization].[uspOrgAddressXrefInsertOut] @piOrgId=@iSubLocationOrgId, @pbiAddressId=@biAddressId, @pfLatitude=-1, @pfLongitude=-1, @piStatusFlag=@iStatusFlag, @pnvUserName=@nvUserName, @piOrgAddressXrefId = @iOrgAddressXrefId output;
			END
			UPDATE o
				SET SubLocationOrgId = @iSubLocationOrgId
					,LocationOrgId = @iOPAtmLocationOrgId
			FROM #PNCOrganizationInsert o
			WHERE BulkOrganizationId = @biBulkOrganizationId;
		END

		FETCH csr_subLocation INTO @biBulkOrganizationId, @nvOrgName, @nvOrgCode, @nvExternalCode, @nvAddress1, @nvAddress2, @nvCity, @nvStateCode, @ncZipCode
	END
	CLOSE csr_subLocation;
	DEALLOCATE csr_subLocation; 

	SELECT * FROM #PNCOrganizationInsert;

	--Build org CrossReferences
 	DECLARE csr_OrgXref CURSOR FOR
	--client to partner
	SELECT DISTINCT BulkOrganizationId
		,@iOrganizationDimensionId as DimensionId
		,@iPartnerOrgId as OrgParentId
		,ClientOrgId as OrgChildId
	FROM #PNCOrganizationInsert
	UNION ALL--loc to client
	SELECT DISTINCT BulkOrganizationId
		,@iOrganizationDimensionId as DimensionId
		,ClientOrgId as OrgParentId
		,LocationOrgId as OrgChildId
	FROM #PNCOrganizationInsert
	UNION ALL--subloc to location
	SELECT DISTINCT BulkOrganizationId
		,@iOrganizationDimensionId as DimensionId
		,LocationOrgId as OrgParentId
		,SubLocationOrgId as OrgChildId
	FROM #PNCOrganizationInsert
	UNION ALL--loc to risk
 	SELECT DISTINCT BulkOrganizationId
		,@iRiskControlDimensionId as DimensionId
		,RiskControlOrgId as OrgParentId
		,LocationOrgId as OrgChildId
	FROM #PNCOrganizationInsert 	
	UNION ALL--subloc to risk
 	SELECT DISTINCT BulkOrganizationId
		,@iRiskControlDimensionId as DimensionId
		,RiskControlOrgId as OrgParentId
		,SubLocationOrgId as OrgChildId
	FROM #PNCOrganizationInsert
	UNION ALL--loc to geo
 	SELECT DISTINCT BulkOrganizationId
		,@iGeoDimensionId as DimensionId
		,GeoOrgId as OrgParentId
		,LocationOrgId as OrgChildId
	FROM #PNCOrganizationInsert
	WHERE SubLocationOrgId = 0
	UNION ALL--subloc to geo
 	SELECT DISTINCT BulkOrganizationId
		,@iGeoDimensionId as DimensionId
		,GeoOrgId as OrgParentId
		,SubLocationOrgId as OrgChildId
	FROM #PNCOrganizationInsert
	WHERE SubLocationOrgId <> 0
	UNION ALL--loc to channel
 	SELECT DISTINCT BulkOrganizationId
		,@iChannelDimensionId as DimensionId
		,ChannelOrgId as OrgParentId
		,LocationOrgId as OrgChildId
	FROM #PNCOrganizationInsert
 	UNION ALL--subloc to channel
 	SELECT DISTINCT BulkOrganizationId
		,@iChannelDimensionId as DimensionId
		,ChannelOrgId as OrgParentId
		,SubLocationOrgId as OrgChildId
	FROM #PNCOrganizationInsert;	
	OPEN csr_OrgXref
	FETCH csr_OrgXref INTO @biBulkOrganizationId, @iDimensionId, @iOrgParentId, @iOrgChildId;
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
			UPDATE #PNCOrganizationInsert
				SET Processed += 1
			WHERE BulkOrganizationId = @biBulkOrganizationId;
 		FETCH csr_OrgXref INTO @biBulkOrganizationId, @iDimensionId, @iOrgParentId, @iOrgChildId;
	END
	CLOSE csr_OrgXref
	DEALLOCATE csr_OrgXref

	--select 'Post xref' as here,* from @#PNCOrganizationInsert;

	UPDATE pnco
		SET Processed = 1
	FROM [import].[PNCOrganization] pnco
	INNER JOIN #PNCOrganizationInsert o on pnco.BulkOrganizationId = o.BulkOrganizationId
	WHERE o.Processed >= 6 --means we added all orgxrefs successfully
		AND ClientOrgId > 0	 --client exists
		AND LocationOrgId > 0; --location exists

	END
END

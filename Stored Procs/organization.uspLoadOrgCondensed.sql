USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: [organization].[uspLoadOrgCondensed]
	CreatedBy: Larry Dugger
	Description: Load [dbo].[UtilityOrg]

	History:
		2020-12-19 - LBD - Created
*****************************************************************************************/
ALTER   PROCEDURE [organization].[uspLoadOrgCondensed]
AS
BEGIN
	DROP TABLE IF EXISTS #tblOrgDim;
	CREATE TABLE #tblOrgDim(
		 LevelId nvarchar(25) 
		,ParentId int
		,OrgId int primary key
		,OrgCode nvarchar(25)
		,OrgName nvarchar(50)
		,ExternalCode nvarchar(50)
		,OrgDescr nvarchar(255)
		,OrgTypeId int
		,OrgTypeName nvarchar(50)
		,OrgChannel int
		,OrgChannelId int
		,OrgChannelName nvarchar(50)
		,OrgRuleId nvarchar(50)
		,OrgRuleCode nvarchar(25)
		,OrgRiskControlId int
		,OrgRiskControlCode nvarchar(25)
		,OrgGeoLargeId int
		,OrgGeoLargeCode nvarchar(25)
		,OrgGeoSmallId int
		,OrgGeoSmallCode nvarchar(25)
		,OrgGeoZip4Id int
		,OrgGeoZip4Code nvarchar(25)
		,OrgPartnerId int
		,OrgPartnerCode nvarchar(25)
		,OrgClientId int
		,OrgClientCode nvarchar(25)
		,OrgLocationId int
		,OrgLocationCode nvarchar(25)
	);
	DROP TABLE IF EXISTS #tblBase0;
	CREATE TABLE #tblBase0(
		 LevelId nvarchar(25) 
		,ParentId int
		,OrgId int primary key
		,OrgCode nvarchar(25)
		,OrgTypeName nvarchar(50)
		,OrgPartnerId int
		,OrgPartnerCode nvarchar(50)
		,OrgClientId int
		,OrgClientCode nvarchar(50)
		,OrgLocationId int
		,OrgLocationCode nvarchar(50)
	);
	DROP TABLE IF EXISTS #tblBase1;
	CREATE TABLE #tblBase1(
		 LevelId nvarchar(25) 
		,ParentId int
		,OrgId int primary key
		,OrgCode nvarchar(25)
		,OrgTypeName nvarchar(50)
		,OrgPartnerId int
		,OrgPartnerCode nvarchar(50)
		,OrgClientId int
		,OrgClientCode nvarchar(50)
		,OrgLocationId int
		,OrgLocationCode nvarchar(50)
	);
	DECLARE @ncProcessKey nchar(25) = REPLACE(REPLACE(REPLACE(REPLACE(CONVERT(nvarchar(50),sysdatetime(),121),'-',''),' ',''),':',''),'.','');
	DECLARE @iLogLevel int = ISNULL(TRY_CONVERT(INT,[common].[ufnConfigValue](N'LogLevel [organization].[uspLoadOrgCondensed]')),1)
		,@dtTimerDate datetime2(7) = SYSDATETIME()
		,@dtInitial datetime2(7) = SYSDATETIME() --used for complete time in procedure
		,@ncSchemaName nchar(20) = CONVERT(nchar(20),OBJECT_SCHEMA_NAME(@@PROCID))
		,@ncObjectName nchar(50) = CONVERT(nchar(50),OBJECT_NAME(@@PROCID));

	DECLARE @bEnableTimer bit = 1
		,@iErrorDetailId INT
		,@sSchemaName nvarchar(128) = OBJECT_SCHEMA_NAME(@@PROCID)
		,@dt datetime2(7) = sysdatetime();

	IF @iLogLevel > 0
	BEGIN
		INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
		VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Enter' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME()); 
		SET @dtTimerDate = SYSDATETIME()
	END

	INSERT INTO #tblOrgDim(LevelId,ParentId,OrgId,OrgCode,OrgName,ExternalCode,OrgDescr,OrgTypeId,OrgTypeName
		,OrgRuleId,OrgRuleCode,OrgRiskControlId,OrgRiskControlCode,OrgChannelId,OrgChannel,OrgChannelName
		,OrgGeoLargeId,OrgGeoLargeCode,OrgGeoSmallId,OrgGeoSmallCode,OrgGeoZip4Id,OrgGeoZip4Code)
	SELECT LevelId,ParentId,OrgId,OrgCode,OrgName,ExternalCode,OrgDescr,OrgTypeId,OrgTypeName
		,OrgRuleId,OrgRuleCode,OrgRiskControlId,OrgRiskControlCode,OrgChannelId,OrgChannel,OrgChannelName
		,OrgGeoLargeId,OrgGeoLargeCode,OrgGeoSmallId,OrgGeoSmallCode,OrgGeoZip4Id,OrgGeoZip4Code
	FROM [common].[ufnDownOrgDimByOrgIdILTF](99999) order by OrgId;

	CREATE NONCLUSTERED INDEX ix01tblOrgDim ON #tblOrgDim (OrgTypeName)
	INCLUDE (LevelId,OrgId,OrgCode);

	;WITH Basecte(LevelId,ParentId,OrgId,OrgCode,OrgTypeName,OrgPartnerId,OrgPartnerCode,OrgClientId,OrgClientCode,OrgLocationId,OrgLocationCode)
	AS(
		SELECT b.LevelId
			,p.OrgId
			,b.OrgId
			,b.OrgCode
			,b.OrgTypeName
			,CAST(NULL AS int)
			,CAST(NULL AS nvarchar(25))
			,CAST(NULL AS int)
			,CAST(NULL AS nvarchar(25))
			,CAST(NULL AS int)
			,CAST(NULL AS nvarchar(25))
		FROM #tblOrgDim b
		INNER JOIN #tblOrgDim p on b.ParentId = p.OrgId
		WHERE b.OrgTypeName = 'Partner'
		UNION ALL
		--recurse down
		SELECT b.LevelId
			,o.OrgId
			,b.OrgId
			,b.OrgCode
			,b.OrgTypeName
			,CASE WHEN o.OrgTypeName = 'Partner' THEN o.OrgId ELSE NULL END
			,CASE WHEN o.OrgTypeName = 'Partner' THEN o.OrgCode ELSE NULL END
			,CASE WHEN o.OrgTypeName = 'Client' THEN o.OrgId ELSE NULL END
			,CASE WHEN o.OrgTypeName = 'Client' THEN o.OrgCode ELSE NULL END
			,CASE WHEN o.OrgTypeName = 'Location' THEN o.OrgId ELSE NULL END
			,CASE WHEN o.OrgTypeName = 'Location' THEN o.OrgCode ELSE NULL END
		FROM Basecte AS o
		INNER JOIN [organization].[OrgXref] ox on o.OrgId = ox.OrgParentId
		INNER JOIN #tblOrgDim b on ox.OrgChildId = b.OrgId
		WHERE ox.DimensionId = 1 
			AND ox.StatusFlag > 0

	)
	INSERT INTO #tblBase0(LevelId,ParentId,OrgId,OrgCode,OrgTypeName
		,OrgPartnerId, OrgPartnerCode, OrgClientId, OrgClientCode,OrgLocationId,OrgLocationCode)
	SELECT LevelId,ParentId,OrgId,OrgCode,OrgTypeName
		,OrgPartnerId, OrgPartnerCode, OrgClientId, OrgClientCode,OrgLocationId,OrgLocationCode
	FROM Basecte;

	IF EXISTS (SELECT 'X' FROM #tblBase0)
	BEGIN
		INSERT INTO #tblBase1(OrgId,LevelId,ParentId,OrgCode,OrgTypeName,OrgPartnerId,OrgPartnerCode,OrgClientId,OrgClientCode,OrgLocationId,OrgLocationCode)
		SELECT b.OrgId
			,b.LevelId
			,b.ParentId
			,b.OrgCode
			,b.OrgTypeName
			,CASE WHEN b.OrgTypeName not in ('Partner') THEN
				CASE WHEN c.OrgTypeName = 'Partner' THEN c.OrgId 
					WHEN d.OrgTypeName = 'Partner' THEN d.OrgId  
					WHEN e.OrgTypeName = 'Partner' THEN e.OrgId 
					ELSE NULL
				END
				ELSE NULL
			END AS OrgPartnerId
			,CASE WHEN b.OrgTypeName not in ('Partner') THEN
				CASE WHEN c.OrgTypeName = 'Partner' THEN c.OrgCode 
					WHEN d.OrgTypeName = 'Partner' THEN d.OrgCode 
					WHEN e.OrgTypeName = 'Partner' THEN e.OrgCode 
					ELSE NULL
				END
				ELSE NULL
			END AS OrgPartnerCode
			,CASE WHEN b.OrgTypeName not in ('Client','Partner') THEN
				CASE WHEN c.OrgTypeName = 'Client' THEN c.OrgId 
					WHEN d.OrgTypeName = 'Client' THEN d.OrgId 
					ELSE NULL
				END
				ELSE NULL
			END AS OrgClientId
			,CASE WHEN b.OrgTypeName not in ('Client','Partner') THEN
				CASE WHEN c.OrgTypeName = 'Client' THEN c.OrgCode
					WHEN d.OrgTypeName = 'Client' THEN d.OrgCode
					ELSE NULL
				END
				ELSE NULL
			END AS OrgClientCode
			,b.OrgLocationId
			,b.OrgLocationCode
		FROM #tblBase0 b
		LEFT JOIN #tblBase0 c on b.OrgLocationId = c.OrgId 
					or b.ParentId = c.OrgId 
		LEFT JOIN #tblBase0 d on c.OrgClientId = d.OrgId 
				or (c.ParentId = d.OrgId)
		LEFT JOIN #tblBase0 e on d.OrgClientId = e.OrgId 
				or (d.ParentId = e.OrgId) 
		ORDER BY b.OrgId;

		INSERT INTO [new].[OrgCondensed](OrgId,LevelId,ParentId,OrgCode,OrgName,ExternalCode,OrgDescr,OrgTypeId,OrgTypeName,OrgChannel,OrgChannelId
			,OrgChannelName,OrgRuleId,OrgRuleCode,OrgRiskControlId,OrgRiskControlCode,OrgGeoLargeId,OrgGeoLargeCode,OrgGeoSmallId,OrgGeoSmallCode
			,OrgGeoZip4Id,OrgGeoZip4Code,OrgPartnerId,OrgPartnerCode,OrgClientId,OrgClientCode,OrgLocationId,OrgLocationCode,DateActivated)
		SELECT od.OrgId,od.LevelId,od.ParentId,od.OrgCode,od.OrgName,od.ExternalCode,od.OrgDescr,od.OrgTypeId,od.OrgTypeName,od.OrgChannel,od.OrgChannelId
			,od.OrgChannelName,od.OrgRuleId,od.OrgRuleCode,od.OrgRiskControlId,od.OrgRiskControlCode,od.OrgGeoLargeId,od.OrgGeoLargeCode,od.OrgGeoSmallId,od.OrgGeoSmallCode
			,od.OrgGeoZip4Id,od.OrgGeoZip4Code,b1.OrgPartnerId,b1.OrgPartnerCode,b1.OrgClientId,b1.OrgClientCode,b1.OrgLocationId,b1.OrgLocationCode,getdate()
		FROM #tblOrgDim od
		INNER JOIN #tblBase1 b1 on od.OrgId = b1.OrgId;

		--TABLE SWITCHING
		BEGIN TRY
			IF [mac].[ufnTableExists](N'[organization].[OrgCondensed]') = 1
				AND [mac].[ufnTableExists](N'[new].[OrgCondensed]') = 1
				AND [mac].[ufnTableExists](N'[old].[OrgCondensed]') = 1
			BEGIN
				BEGIN TRAN
				--Anyone who tries to query the table after the switch has happened and before
				--the transaction commits will be blocked: we've got a schema mod lock on the table

				--cycle out Current OrgCondensed
				ALTER TABLE [organization].[OrgCondensed] SWITCH TO [old].[OrgCondensed]
					WITH ( WAIT_AT_LOW_PRIORITY ( MAX_DURATION = 1 MINUTES, ABORT_AFTER_WAIT = BLOCKERS ));  

				--Cycle in New OrgCondensed
				ALTER TABLE [new].[OrgCondensed] SWITCH TO [organization].[OrgCondensed]
					WITH ( WAIT_AT_LOW_PRIORITY ( MAX_DURATION = 1 MINUTES, ABORT_AFTER_WAIT = BLOCKERS ));

				-- Cycle Old to New
				ALTER TABLE [old].[OrgCondensed] SWITCH TO [new].[OrgCondensed]
					WITH ( WAIT_AT_LOW_PRIORITY ( MAX_DURATION = 1 MINUTES, ABORT_AFTER_WAIT = BLOCKERS ));  
				COMMIT

				TRUNCATE TABLE [old].[OrgCondensed];
				TRUNCATE TABLE [new].[OrgCondensed];

				IF @iLogLevel > 0
				BEGIN
					INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
					VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Switched AutoFraud',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());  
					SET @dtTimerDate  = SYSDATETIME();
				END
			END
			ELSE --SWITCH New and Current DuplicateItem
			BEGIN
				INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
				VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'OrgCondensed Not Switched',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
				THROW 50000,N'OrgCondensed Not Switched',1;
			END
		END TRY
		BEGIN CATCH
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Exit-ErrorDetailId ='+CONVERT(NCHAR(10),@iErrorDetailId),DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());  		
			THROW
		END CATCH
		--ADJUSTED TO HANDLE THE RETURN LIMIT
		--Last Message uses @dtInitial
		IF @iLogLevel > 0
			INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Exit' 
				,CASE WHEN DATEDIFF(SECOND,@dtInitial,SYSDATETIME()) < 2147 --2017-08-11 LBD
					THEN DATEDIFF(microsecond,@dtInitial,SYSDATETIME())
					ELSE 0
				END
				,SYSDATETIME());  

	END
END

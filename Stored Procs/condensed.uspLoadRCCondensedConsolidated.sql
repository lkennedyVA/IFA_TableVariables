USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/*******************************************************************
	Name: [condensed].[uspLoadRCCondensedConsolidated]
	Created By: Chris Sharp
	Description: Procedure to repopulate the following 
		REMEMBER if any indexes are added to the tables, this procedure
		MUST be updated.
 	 
	Tables:	[condensed].[OrgRCLadderRungCondensed]
		,[condensed].[RCLadderRungCondensed]
		,[condensed].[LadderRungCondensed]
 
	Procedures:

	History:
		2016-11-10 - CBS - Created 		
		2017-01-30 - LBD - Modified, relocated the condensed tables to 
			the condensed schema.
		2017-02-15 - LBD - Modified, loads 'New' table, then switches with Current
			via renaming methodology.
		2017-03-08 - LBD - Modified, now check LadderDBProcessParameterXref for changes.
		2018-08-02 - LBD - Modified, added new index on OrgRCLadderRungCondensed.
		2018-08-16 - LBD - Modified, use switching instead of renaming
		2021-03-04 - CBS - Added call to import.uspOrganizationLog if @pbImportLog = 1.  
			By default, we do not log that the procedure was executed
		2025-01-08 - LXK - Removed table variables
*****************************************************************************************/
ALTER PROCEDURE [condensed].[uspLoadRCCondensedConsolidated](
	@pbImportLog BIT = 0 --2021-03-04
)
AS
BEGIN
	drop table if exists #LadderTopRung0
	create table #LadderTopRung0(
		 LadderTopId int
		,Id int
		,LadderDBProcessXrefId int
		,RPName nvarchar(50)
		,CollectionName nvarchar(50)
		,LadderCode nvarchar(25)
		,Title nvarchar(50)
		,ProcessCode nvarchar(50)
		,ProcessName nvarchar(50)
		,DBProcessSuccessValue nvarchar(512)
		,DBProcessSuccessLDBPXId int
		,DBProcessContinueLDBPXId int
		,Param1 nvarchar(512)
		,Param2 nvarchar(512)
		,Param3 nvarchar(512)
		,Param4 nvarchar(512)
		,Param5 nvarchar(512)
		,ExitLevel nvarchar(512)
		,Result nvarchar(512)
		,RetrievalType nvarchar(25)
		,RetrievalCode nvarchar(25)
	);
	drop table if exists #LadderTopRung
	create table #LadderTopRung(
		 LadderTopRungId int identity(1,1)	
		,LadderTopId int
		,Id int
		,LadderDBProcessXrefId int
		,RPName nvarchar(50)
		,CollectionName nvarchar(50)
		,LadderCode nvarchar(25)
		,Title nvarchar(50)
		,ProcessCode nvarchar(50)
		,ProcessName nvarchar(50)
		,DBProcessSuccessValue nvarchar(512)
		,DBProcessSuccessLDBPXId int
		,DBProcessContinueLDBPXId int
		,Param1 nvarchar(512)
		,Param2 nvarchar(512)
		,Param3 nvarchar(512)
		,Param4 nvarchar(512)
		,Param5 nvarchar(512)
		,ExitLevel nvarchar(512)
		,Result nvarchar(512)
		,RetrievalType nvarchar(25)
		,RetrievalCode nvarchar(25)
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
	);
	drop table if exists #LadderDBProcessXref
   create table #LadderDBProcessXref(
		 LadderTopId int
		,LadderDBProcessXrefId int
		,RPName nvarchar(50)
		,CollectionName nvarchar(50)
	);
	drop table if exists #LadderDBProcessParameterXref
   create table #LadderDBProcessParameterXref(
		 Id int
		,LadderDBprocessXrefId int
		,Param1 nvarchar(512)
		,Param2 nvarchar(512)
		,Param3 nvarchar(512)
		,Param4 nvarchar(512)
		,Param5 nvarchar(512)
		,ExitLevel nvarchar(512)
		,Result nvarchar(512)
	);
	drop table if exists #OrgList
	create table #OrgList(
		OrgId int
	);
	drop table if exists #OrgRCLadderRungCondensed
	create table #OrgRCLadderRungCondensed(
		 RCLadderTopId int
		,RCCollectionName nvarchar(50)
		,DimensionName nvarchar(50)
		,ParentOrgId int
		,ChildOrgId int
		,LadderTopXrefId int 
		,LadderTopId int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
	);
	drop table if exists #RCLadderTopRung
	create table #RCLadderTopRung(
	     RCLadderTopRungId int identity(1,1)
		,RCLadderTopId int
		,Id int
		,RCId int
		,RCName nvarchar(50)
		,OrgXrefId int
		,DimensionName nvarchar(50)
		,OrgName nvarchar(50)
		,OrgType nvarchar(50)
		,LadderTopXrefId int
		,CollectionName nvarchar(100)
		,LadderTopId int
		,LadderCollectionName nvarchar(100)
		,LadderSuccessValue nvarchar(50)
		,LadderSuccessLTXId int
		,SuccessLtId int
		,LadderContinueLTXId int
		,ContinueLtId int
	);
	drop table if exists #RCLadderTopRung0
	create table #RCLadderTopRung0(
		 RCLadderTopId int
		,Id int
		,RCId int
		,RCName nvarchar(50)
		,OrgXrefId int
		,DimensionName nvarchar(50)
		,OrgName nvarchar(50)
		,OrgType nvarchar(50)
		,LadderTopXrefId int
		,CollectionName nvarchar(100)
		,LadderTopId int
		,LadderCollectionName nvarchar(100)
		,LadderSuccessValue nvarchar(50)
		,LadderSuccessLTXId int
		,SuccessLtId int
		,LadderContinueLTXId int
		,ContinueLtId int
	);
   drop table if exists #RCLadderTop
   create table #RCLadderTop(
		 RCLadderTopId int
		,RCId int
		,RCName nvarchar(50)
		,OrgXrefId int
		,DimensionName nvarchar(50)
		,OrgName nvarchar(50)
		,OrgType nvarchar(50)
		,LadderTopXrefId int
		,LadderTopId int
		,CollectionName nvarchar(100)
	);
	drop table if exists #LadderTopXref
	create table #LadderTopXref(
		 LadderTopXrefId  int
	);
			 
	DECLARE @bImportLog bit = @pbImportLog --2021-03-04
		,@nvMsg nvarchar(256) --2021-03-04
		,@iRCLadderTopId int
		,@iLadderTopId int
		,@dtDateArchived datetime2(7)
		,@dtDateActivated datetime2(7) = SYSDATETIME()
		,@nvUserName nvarchar(100) = 'System'
		,@iOrgId bigint
		,@dtReferenceDate datetime2(7) = SYSDATETIME()
		,@dtMaxDateOrclrc datetime2(7)
		,@dtMaxDateRclt datetime2(7)
		,@dtMaxDateRc datetime2(7)
		,@dtMaxDateOxr datetime2(7)
		,@dtMaxDateO datetime2(7)
		,@dtMaxDateOt datetime2(7)
		,@dtMaxDateLt datetime2(7)
		,@dtMaxDateLtx datetime2(7)
		,@dtMaxDateLdbpx datetime2(7)
		,@dtMaxDateLdbppx datetime2(7);

	SELECT @dtMaxDateOrclrc = ISNULL(MAX(DateActivated), '1900-01-01')
	FROM [condensed].[OrgRCLadderRungCondensed] orclrc ;
	SELECT @dtMaxDateRclt = ISNULL(MAX(DateActivated), '1900-01-01')
	FROM [riskprocessing].[RCLadderTop] rclt ;
	SELECT @dtMaxDateRc = ISNULL(MAX(DateActivated), '1900-01-01')
	FROM [riskprocessing].[RC] rc ;
	SELECT @dtMaxDateLt = ISNULL(MAX(DateActivated), '1900-01-01')
	FROM [riskprocessing].[LadderTop] lt ;
	SELECT @dtMaxDateLtx = ISNULL(MAX(DateActivated), '1900-01-01')
	FROM [riskprocessing].[LadderTopXref] ltx ;
	SELECT @dtMaxDateLtx = ISNULL(MAX(DateActivated), '1900-01-01')
	FROM [riskprocessing].[LadderTopXref] ltx ;
	SELECT @dtMaxDateLdbpx = ISNULL(MAX(DateActivated), '1900-01-01')
	FROM [riskprocessing].[LadderDBProcessXref] ldbpx ;
	SELECT @dtMaxDateLdbppx = ISNULL(MAX(DateActivated), '1900-01-01')
	FROM [riskprocessing].[LadderDBProcessParameterXref] ldbpx ;
	SELECT @dtMaxDateOxr = ISNULL(MAX(DateActivated), '1900-01-01')
	FROM [organization].[OrgXref] oxr ;
	SELECT @dtMaxDateO = ISNULL(MAX(DateActivated), '1900-01-01')
	FROM [organization].[Org] o ;
	SELECT @dtMaxDateOt = ISNULL(MAX(DateActivated), '1900-01-01')
	FROM [organization].[OrgType] ot ;

	IF @dtMaxDateOrclrc < @dtMaxDateRclt 
		OR @dtMaxDateOrclrc < @dtMaxDateRc
		OR @dtMaxDateOrclrc < @dtMaxDateLt
		OR @dtMaxDateOrclrc < @dtMaxDateLtx
		OR @dtMaxDateOrclrc < @dtMaxDateLdbpx
		OR @dtMaxDateOrclrc < @dtMaxDateLdbppx
		OR @dtMaxDateOrclrc < @dtMaxDateOxr
		OR @dtMaxDateOrclrc < @dtMaxDateO
		OR @dtMaxDateOrclrc < @dtMaxDateOt
	BEGIN
		--RP Structures first
		--OLD fashioned pivot
		INSERT INTO #LadderDBProcessParameterXref(LadderDBProcessXrefId,Param1,Param2,Param3,Param4,Param5,ExitLevel,Result)
		SELECT ldbpx.LadderDBProcessXrefId
			,Param1=MAX(CASE WHEN p.Code = 'Param1' THEN pv.Value END)
			,Param2=MAX(CASE WHEN p.Code = 'Param2' THEN pv.Value END)
			,Param3=MAX(CASE WHEN p.Code = 'Param3' THEN pv.Value END)
			,Param4=MAX(CASE WHEN p.Code = 'Param4' THEN pv.Value END)
			,Param5=MAX(CASE WHEN p.Code = 'Param5' THEN pv.Value END)
			,ExitLevel=MAX(CASE WHEN p.Code = 'ExitLevel' THEN pv.Value END)
			,Result=MAX(CASE WHEN p.Code = 'Result' THEN pv.Value END)	
		FROM [riskprocessing].[LadderDBProcessXref] ldbpx
		INNER JOIN [riskprocessing].[LadderDBProcessParameterXref] ldbppx on ldbpx.LadderDBProcessXrefId = ldbppx.LadderDBProcessXrefId
		INNER JOIN [riskprocessing].[DBProcessParameterXref] dbppx on ldbppx.DBProcessParameterXrefId = dbppx.DBProcessParameterXrefId
		INNER JOIN [riskprocessing].[Parameter] p on dbppx.ParameterId = p.ParameterId
		INNER JOIN [riskprocessing].[ParameterValueXref] pvx on ldbppx.ParameterValueXrefId = pvx.ParameterValueXrefId
		INNER JOIN [riskprocessing].[ParameterValue] pv on pvx.ParameterValueId = pv.ParameterValueId 
		WHERE ldbpx.DateActivated <= SYSDATETIME()
			AND ldbpx.StatusFlag = 1
			AND ldbppx.DateActivated <= SYSDATETIME()
			AND ldbppx.StatusFlag = 1
			AND dbppx.DateActivated <= SYSDATETIME()
			AND dbppx.StatusFlag = 1
			AND p.DateActivated <= SYSDATETIME()
			AND p.StatusFlag = 1
			AND pvx.DateActivated <= SYSDATETIME()
			AND pvx.StatusFlag = 1
			AND pv.DateActivated <= SYSDATETIME()
			AND pv.StatusFlag = 1
		GROUP BY ldbpx.LadderDBProcessXrefId;

		DECLARE csr_Insert CURSOR FOR
		SELECT LadderTopId
		FROM [riskprocessing].[LadderTop]
		WHERE StatusFlag > 0
			AND DateActivated <= SYSDATETIME()
		ORDER BY LadderTopId;
		OPEN csr_Insert;
		FETCH csr_Insert INTO @iLadderTopId;
		WHILE @@FETCH_STATUS = 0
		BEGIN
			--Collect Info for this Node
			INSERT INTO #LadderDBProcessXref(LadderTopId,LadderDBProcessXrefId,RPName,CollectionName)
			SELECT lt.LadderTopId 
				,ldbpx.LadderDBProcessXrefId
				,r.Name as RPName
				,lt.CollectionName
			FROM [riskprocessing].[LadderTop] lt 
			INNER JOIN [riskprocessing].[RP] r on lt.RPId = r.RPId
			INNER JOIN [riskprocessing].[LadderDBProcessXref] ldbpx on lt.LadderDBProcessXrefId = ldbpx.LadderDBProcessXrefId
			WHERE lt.LadderTopId = @iLadderTopId
				AND lt.DateActivated <= SYSDATETIME()
				AND lt.StatusFlag > 0
				AND r.DateActivated <= SYSDATETIME()
				AND r.StatusFlag > 0
				AND ldbpx.DateActivated <= SYSDATETIME()
				AND ldbpx.StatusFlag = 1;
			--BUILD CTE
			WITH LadderDBProcessCTE(LadderTopId,Id,LadderDBProcessXrefId
				,RPName,CollectionName,LadderCode,Title,ProcessCode,ProcessName,DBProcessSuccessValue,DBProcessSuccessLDBPXId
				,DBProcessContinueLDBPXId,Param1,Param2,Param3,Param4,Param5,ExitLevel,Result,RetrievalType,RetrievalCode)
			AS(
				--SET the starting point,hence 1 for the id
				SELECT ldbpx2.LadderTopId,1,ldbpx.LadderDBProcessXrefId
					,ldbpx2.RPName,ldbpx2.CollectionName,c.Code,ldbpx.Title,d.Code,d.Name
					,ldbpx.DBProcessSuccessValue
					,ldbpx.DBProcessSuccessLDBPXId as Child1
					,ldbpx.DBProcessContinueLDBPXId as Child2
					,pvt.Param1,pvt.Param2,pvt.Param3,pvt.Param4,pvt.Param5,pvt.Exitlevel,pvt.Result,d.RetrievalType,d.RetrievalCode
				FROM [riskprocessing].[LadderDBProcessXref] ldbpx
				INNER JOIN #LadderDBProcessXref ldbpx2 on ldbpx.LadderDBProcessXrefId = ldbpx2.LadderDBProcessXrefId
				INNER JOIN [riskprocessing].[Ladder] c on ldbpx.LadderId = c.LadderId
				INNER JOIN [riskprocessing].[DBProcess] d on ldbpx.DBProcessId = d.DBProcessId
				INNER JOIN #LadderDBProcessParameterXref as pvt on ldbpx.LadderDBProcessXrefId = pvt.LadderDBProcessXrefId
				WHERE ldbpx.DateActivated <= SYSDATETIME()
					AND ldbpx.StatusFlag = 1
					AND c.DateActivated <= SYSDATETIME()
					AND c.StatusFlag = 1
				UNION ALL
				--RECURSE down Success, setting all children to an id of 2 because their order is not important
				SELECT cdbpc.LadderTopId,2,ldbpx.LadderDBProcessXrefId
					,cdbpc.RPName,cdbpc.CollectionName,c.Code,ldbpx.Title,d.Code,d.Name
					,ldbpx.DBProcessSuccessValue
					,ldbpx.DBProcessSuccessLDBPXId as Child1
					,ldbpx.DBProcessContinueLDBPXId as Child2
					,pvt.Param1,pvt.Param2,pvt.Param3,pvt.Param4,pvt.Param5,pvt.ExitLevel,pvt.Result,d.RetrievalType,d.RetrievalCode
				FROM LadderDBProcessCTE cdbpc
				INNER JOIN [riskprocessing].[LadderDBProcessXref] ldbpx on cdbpc.DBProcessSuccessLDBPXId = ldbpx.LadderDBProcessXrefId
				INNER JOIN [riskprocessing].[Ladder] c on ldbpx.LadderId = c.LadderId
				INNER JOIN [riskprocessing].[DBProcess] d on ldbpx.DBProcessId = d.DBProcessId
				INNER JOIN #LadderDBProcessParameterXref as pvt on ldbpx.LadderDBProcessXrefId = pvt.LadderDBProcessXrefId
				WHERE ldbpx.DateActivated <= SYSDATETIME()
					AND ldbpx.StatusFlag = 1
					AND c.DateActivated <= SYSDATETIME()
					AND c.StatusFlag = 1
				UNION ALL
				--RECURSE down Continue, setting all children to an id of 2 because their order is not important
				SELECT cdbpc.LadderTopId,2,ldbpx.LadderDBProcessXrefId
					,cdbpc.RPName,cdbpc.CollectionName,c.Code,ldbpx.Title,d.Code,d.Name
					,ldbpx.DBProcessSuccessValue
					,ldbpx.DBProcessSuccessLDBPXId as Child1
					,ldbpx.DBProcessContinueLDBPXId as Child2
					,pvt.Param1,pvt.Param2,pvt.Param3,pvt.Param4,pvt.Param5,pvt.ExitLevel,pvt.Result,d.RetrievalType,d.RetrievalCode
				FROM LadderDBProcessCTE cdbpc
				INNER JOIN [riskprocessing].[LadderDBProcessXref] ldbpx on cdbpc.DBProcessContinueLDBPXId = ldbpx.LadderDBProcessXrefId
				INNER JOIN [riskprocessing].[Ladder] c on ldbpx.LadderId = c.LadderId
				INNER JOIN [riskprocessing].[DBProcess] d on ldbpx.DBProcessId = d.DBProcessId 
				INNER JOIN #LadderDBProcessParameterXref as pvt on ldbpx.LadderDBProcessXrefId = pvt.LadderDBProcessXrefId
				WHERE ldbpx.DateActivated <= SYSDATETIME()
					AND ldbpx.StatusFlag = 1
					AND c.DateActivated <= SYSDATETIME()
					AND c.StatusFlag = 1
			)
			INSERT INTO #LadderTopRung0(LadderTopId,Id,LadderDBProcessXrefId
				,RPName,CollectionName,LadderCode,Title,ProcessCode,ProcessName,DBProcessSuccessValue,DBProcessSuccessLDBPXId,DBProcessContinueLDBPXId
				,Param1,Param2,Param3,Param4,Param5,ExitLevel,Result,RetrievalType,RetrievalCode)
			SELECT distinct LadderTopId,Id,LadderDBProcessXrefId
				,RPName,CollectionName,LadderCode,Title,ProcessCode,ProcessName,DBProcessSuccessValue,DBProcessSuccessLDBPXId,DBProcessContinueLDBPXId
				,Param1,Param2,Param3,Param4,Param5,ExitLevel,Result,RetrievalType,RetrievalCode
			FROM LadderDBProcessCTE
			ORDER BY Id;
			INSERT INTO #LadderTopRung(LadderTopId,Id,LadderDBProcessXrefId
				,RPName,CollectionName,LadderCode,Title,ProcessCode,ProcessName,DBProcessSuccessValue,DBProcessSuccessLDBPXId,DBProcessContinueLDBPXId
				,Param1,Param2,Param3,Param4,Param5,ExitLevel,Result,RetrievalType,RetrievalCode)
			SELECT LadderTopId,ROW_NUMBER() OVER (ORDER BY Id) as Id,LadderDBProcessXrefId
				,RPName,CollectionName,LadderCode,Title,ProcessCode,ProcessName,DBProcessSuccessValue,DBProcessSuccessLDBPXId,DBProcessContinueLDBPXId
				,Param1,Param2,Param3,Param4,Param5,ExitLevel,Result,RetrievalType,RetrievalCode
			FROM #LadderTopRung0
			ORDER BY Id;
			DELETE FROM #LadderDBProcessXref;
			DELETE FROM #LadderTopRung0;
			FETCH csr_Insert into @iLadderTopId;
		END
		CLOSE csr_Insert;
		DEALLOCATE csr_Insert;

		DECLARE csr_Insert CURSOR FOR
		SELECT RCLadderTopId
		FROM [riskprocessing].[RCLadderTop]
		WHERE StatusFlag > 0
			AND DateActivated <= SYSDATETIME()
		ORDER BY RCLadderTopId;
		OPEN csr_Insert;
		FETCH csr_Insert INTO @iRCLadderTopId;
		WHILE @@FETCH_STATUS = 0
		BEGIN
			--Find the Starting Point(s)
			INSERT INTO #RCLadderTop(RCLadderTopId,RCId,RCName,OrgXrefId,DimensionName,OrgName,OrgType,LadderTopXrefId,LadderTopId,CollectionName)
			SELECT RCLadderTopId,RCId,RCName,OrgXrefId,DimensionName,OrgName,OrgType,LadderTopXrefId,LadderTopId,CollectionName
			FROM [riskprocessing].[ufnRCLadderTop](@iRCLadderTopId);
			--BUILD CTE
			WITH RCLadderTopRungCTE(RCLadderTopId,Id,RCId,RCName,OrgXrefId,DimensionName,OrgName,OrgType,LadderTopXrefId,CollectionName
				,LadderTopId,LadderCollectionName,LadderSuccessValue,LadderSuccessLTXId,LadderContinueLTXId)
			AS(
				--set the starting point
				SELECT rclt.RCLadderTopId,1,rclt.RCId,rclt.RCName,rclt.OrgXrefId,rclt.DimensionName
					,rclt.OrgName,rclt.OrgType,ltx.LadderTopXrefId,rclt.CollectionName
					,ltx.LadderTopId
					,lt.CollectionName as LadderCollectionName
					,ltx.LadderSuccessValue
					,ltx.LadderSuccessLTXId as Child1
					,ltx.LadderContinueLTXId as Child2
				FROM #RCLadderTop rclt
				INNER JOIN [riskprocessing].[LadderTopXref] ltx ON rclt.LadderTopXrefId = ltx.LadderTopXrefId
				INNER JOIN [riskprocessing].[LadderTop] lt on ltx.LadderTopId = lt.LadderTopId
				WHERE ltx.DateActivated <= SYSDATETIME()
					AND ltx.StatusFlag = 1
					AND lt.DateActivated <= SYSDATETIME()
					AND lt.StatusFlag = 1
				UNION ALL
				--recurse down Success
				SELECT rcltx.RCLadderTopId,2,rcltx.RCId,rcltx.RCName,rcltx.OrgXrefId,rcltx.DimensionName
					,rcltx.OrgName,rcltx.OrgType,ltx.LadderTopXrefId,rcltx.CollectionName
					,ltx.LadderTopId
					,lt.CollectionName as LadderCollectionName
					,ltx.LadderSuccessValue
					,ltx.LadderSuccessLTXId as Child1
					,ltx.LadderContinueLTXId as Child2
				FROM RCLadderTopRungCTE rcltx
				INNER JOIN [riskprocessing].[LadderTopXref] ltx  on rcltx.LadderSuccessLTXId = ltx.LadderTopXrefId
				INNER JOIN [riskprocessing].[LadderTop] lt on ltx.LadderTopId = lt.LadderTopId
				WHERE ltx.DateActivated <= SYSDATETIME()
					AND ltx.StatusFlag = 1
					AND lt.DateActivated <= SYSDATETIME()
					AND lt.StatusFlag = 1
				UNION ALL
				--recurse down Continue
				SELECT rcltx.RCLadderTopId,2,rcltx.RCId,rcltx.RCName,rcltx.OrgXrefId,rcltx.DimensionName
					,rcltx.OrgName,rcltx.OrgType,ltx.LadderTopXrefId,rcltx.CollectionName
					,ltx.LadderTopId
					,lt.CollectionName as LadderCollectionName
					,ltx.LadderSuccessValue
					,ltx.LadderSuccessLTXId as Child1
					,ltx.LadderContinueLTXId as Child2
				FROM RCLadderTopRungCTE rcltx
				INNER JOIN [riskprocessing].[LadderTopXref] ltx  on rcltx.LadderContinueLTXId = ltx.LadderTopXrefId
				INNER JOIN [riskprocessing].[LadderTop] lt on ltx.LadderTopId = lt.LadderTopId
				WHERE ltx.DateActivated <= SYSDATETIME()
					AND ltx.StatusFlag = 1
					AND lt.DateActivated <= SYSDATETIME()
					AND lt.StatusFlag = 1
			)
			INSERT INTO #RCLadderTopRung0(RCLadderTopId,Id,RCId,RCName,OrgXrefId,DimensionName,OrgName,OrgType,LadderTopXrefId,
				CollectionName,LadderTopId,LadderCollectionName,LadderSuccessValue,LadderSuccessLTXId,LadderContinueLTXId)
			SELECT DISTINCT RCLadderTopId,Id,RCId,RCName,OrgXrefId,DimensionName,OrgName,OrgType,LadderTopXrefId,
				CollectionName,LadderTopId,LadderCollectionName,LadderSuccessValue,LadderSuccessLTXId,LadderContinueLTXId
			FROM RCLadderTopRungCTE
			ORDER BY Id;
			INSERT INTO #RCLadderTopRung(RCLadderTopId,Id,RCId,RCName,OrgXrefId,DimensionName,OrgName,OrgType,LadderTopXrefId,
				CollectionName,LadderTopId,LadderCollectionName,LadderSuccessValue,LadderSuccessLTXId,LadderContinueLTXId)
			SELECT RCLadderTopId,ROW_NUMBER() OVER (ORDER BY Id) as Id,RCId,RCName,OrgXrefId,DimensionName,OrgName,OrgType,LadderTopXrefId,
				CollectionName,LadderTopId,LadderCollectionName,LadderSuccessValue,LadderSuccessLTXId,LadderContinueLTXId
			FROM #RCLadderTopRung0
			ORDER BY Id;
			DELETE FROM #RCLadderTop;
			DELETE FROM #RCLadderTopRung0;
			FETCH csr_Insert INTO @iRCLadderTopId;
		END
		CLOSE csr_Insert;
		DEALLOCATE csr_Insert;
		UPDATE r
			SET ContinueLtId = ISNULL(ltx.LadderTopId,0)
		FROM #RCLadderTopRung r
		LEFT OUTER JOIN [riskprocessing].[LadderTopXref] ltx on r.LadderContinueLTXId = ltx.LadderTopXrefId
		WHERE ltx.Title like '%'+r.CollectionName;
		UPDATE r
			SET SuccessLtId = ISNULL(ltx.LadderTopId,0)
		FROM #RCLadderTopRung r
		LEFT OUTER JOIN [riskprocessing].[LadderTopXref] ltx on r.LadderSuccessLTXId = ltx.LadderTopXrefId
		WHERE ltx.Title like '%'+r.CollectionName;

		--ADD new
		INSERT INTO #OrgList(OrgId)
		SELECT ox.OrgChildId
		FROM [organization].[OrgXref] ox  
		INNER JOIN [common].[Dimension] d  ON ox.DimensionId = d.DimensionId
		WHERE d.[Name] = 'RiskControl'
			AND d.StatusFlag = 1
			AND d.DateActivated <= SYSDATETIME()
			AND ox.StatusFlag = 1
			AND ox.DateActivated <= SYSDATETIME();

		DECLARE csr_RCCXref CURSOR FAST_FORWARD FOR
		SELECT OrgId
		FROM #OrgList

		OPEN csr_RCCXref 
			FETCH NEXT FROM csr_RCCXref INTO @iOrgId
			WHILE @@FETCH_STATUS = 0 
			BEGIN
			INSERT INTO #OrgRCLadderRungCondensed(
				 RCLadderTopId
				,RCCollectionName
				,DimensionName
				,ParentOrgId
				,ChildOrgId
				,LadderTopXrefId 
				,LadderTopId 
				,DateActivated 
				,UserName 
				)
			SELECT RCLadderTopId, CollectionName, DimensionName, OrgId, @iOrgId, LadderTopXrefId, LadderTopId, @dtDateActivated, @nvUserName --2016-11-11
			FROM [riskprocessing].[ufnRCLadderTopByOrg](@iOrgId) rclt
			WHERE OrgId <> @iOrgId;  --ParentOrgId <> ChildOrgId, we only want the children

			FETCH NEXT FROM csr_RCCXref INTO @iOrgId
		END
		CLOSE csr_RCCXref 
		DEALLOCATE csr_RCCXref;

		--ARCHIVE the current
		INSERT INTO [archive].[LadderRungCondensed](LadderRungCondensedId, LadderTopId, Id, LadderDBProcessXrefId
			,RPName ,CollectionName, LadderCode, Title, ProcessCode, ProcessName, DBProcessSuccessValue, DBProcessSuccessLDBPXId, DBProcessContinueLDBPXId
			,Param1, Param2, Param3, Param4, Param5, ExitLevel, Result, RetrievalType, RetrievalCode, StatusFlag, DateActivated, UserName, DateArchived)
		SELECT LadderRungCondensedId, LadderTopId, Id, LadderDBProcessXrefId
			,RPName ,CollectionName, LadderCode, Title, ProcessCode, ProcessName, DBProcessSuccessValue, DBProcessSuccessLDBPXId, DBProcessContinueLDBPXId
			,Param1, Param2, Param3, Param4, Param5, ExitLevel, Result, RetrievalType, RetrievalCode, StatusFlag, DateActivated, @nvUserName, @dtDateActivated
		FROM [condensed].[LadderRungCondensed];

		INSERT INTO [archive].[RCLadderRungCondensed](RCLadderRungCondensedId, RCLadderTopId, Id, RCId, RCName, OrgXrefId, DimensionName, OrgName
			,OrgType, LadderTopXrefId, CollectionName, LadderTopId, LadderCollectionName, LadderSuccessValue, LadderSuccessLTXId, SuccessLtId
			,LadderContinueLTXId, ContinueLtId, StatusFlag, DateActivated, UserName, DateArchived)
		SELECT RCLadderRungCondensedId, RCLadderTopId, Id, RCId, RCName, OrgXrefId, DimensionName, OrgName
			,OrgType, LadderTopXrefId, CollectionName, LadderTopId, LadderCollectionName, LadderSuccessValue, LadderSuccessLTXId, SuccessLtId
			,LadderContinueLTXId, ContinueLtId, StatusFlag, DateActivated, 'System', @dtDateActivated
		FROM [condensed].[RCLadderRungCondensed];

		INSERT INTO [archive].[OrgRCLadderRungCondensed](OrgRCLadderRungCondensedId, RCCollectionName, DimensionName, RCLadderTopId, ParentOrgId
			,ChildOrgId, LadderTopXrefId, LadderTopId, DateActivated, UserName, DateArchived)
		SELECT OrgRCLadderRungCondensedId, RCCollectionName, DimensionName, RCLadderTopId, ParentOrgId, ChildOrgId
			,LadderTopXrefId, LadderTopId, DateActivated, UserName, @dtDateActivated
		FROM [condensed].[OrgRCLadderRungCondensed];

		--REMOVE prior data in the 'New' tables
		EXECUTE [condensed].[uspTruncateTable] @pnvTargetTable='[new].[LadderRungCondensed]'
		EXECUTE [condensed].[uspTruncateTable] @pnvTargetTable='[new].[RCLadderRungCondensed]'
		EXECUTE [condensed].[uspTruncateTable] @pnvTargetTable='[new].[OrgRCLadderRungCondensed]'

		--INSERT new
		INSERT INTO [new].[LadderRungCondensed](LadderTopId, Id, LadderDBProcessXrefId
			,RPName ,CollectionName, LadderCode, Title, ProcessCode, ProcessName, DBProcessSuccessValue, DBProcessSuccessLDBPXId, DBProcessContinueLDBPXId
			,Param1, Param2, Param3, Param4, Param5, ExitLevel, Result, RetrievalType, RetrievalCode, StatusFlag, DateActivated, UserName)
		SELECT LadderTopId, Id, LadderDBProcessXrefId
			,RPName ,CollectionName, LadderCode, Title, ProcessCode, ProcessName, DBProcessSuccessValue, DBProcessSuccessLDBPXId, DBProcessContinueLDBPXId
			,Param1, Param2, Param3, Param4, Param5, ExitLevel, Result, RetrievalType, RetrievalCode, 1, @dtDateActivated, @nvUserName 
		FROM #LadderTopRung ltr
		ORDER BY LadderTopRungid;

		INSERT INTO [new].[RCLadderRungCondensed](RCLadderTopId,Id,RCId,RCName,OrgXrefId,DimensionName,OrgName,OrgType,LadderTopXrefId,
			CollectionName,LadderTopId,LadderCollectionName,LadderSuccessValue,LadderSuccessLTXId,SuccessLtId,LadderContinueLTXId,ContinueLtId,StatusFlag,DateActivated,UserName)
		SELECT RCLadderTopId,Id,RCId,RCName,OrgXrefId,DimensionName,OrgName,OrgType,LadderTopXrefId,
			CollectionName,LadderTopId,LadderCollectionName,LadderSuccessValue,LadderSuccessLTXId,SuccessLtId,LadderContinueLTXId,ContinueLtId,1,@dtDateActivated,@nvUserName
		FROM #RCLadderTopRung
		ORDER BY RCLadderTopRungId;

		INSERT INTO [new].[OrgRCLadderRungCondensed](
			RCLadderTopId,RCCollectionName,DimensionName,ParentOrgId,ChildOrgId ,LadderTopXrefId,LadderTopId,DateActivated,UserName)
		SELECT RCLadderTopId,RCCollectionName,DimensionName,ParentOrgId,ChildOrgId ,LadderTopXrefId,LadderTopId,DateActivated,UserName
		FROM #OrgRCLadderRungCondensed;

		--NOW switch the tables, minimizing impact

		BEGIN TRAN
			--Anyone who tries to query the table after the switch has happened and before
			--the transaction commits will be blocked: we've got a schema mod lock on the table

			--cycle out Current LadderRungCondensed
			ALTER TABLE [Condensed].[condensed].[LadderRungCondensed] SWITCH PARTITION 1 TO [Condensed].[old].[LadderRungCondensed] PARTITION 1
				WITH ( WAIT_AT_LOW_PRIORITY ( MAX_DURATION = 1 MINUTES, ABORT_AFTER_WAIT = BLOCKERS ));  

			--Cycle in New LadderRungCondensed
			ALTER TABLE [Condensed].[new].[LadderRungCondensed] SWITCH PARTITION 1 TO [Condensed].[condensed].[LadderRungCondensed] PARTITION 1
				WITH ( WAIT_AT_LOW_PRIORITY ( MAX_DURATION = 1 MINUTES, ABORT_AFTER_WAIT = BLOCKERS ));

			-- Cycle Old to New
			ALTER TABLE [Condensed].[old].[LadderRungCondensed] SWITCH PARTITION 1 TO [Condensed].[new].[LadderRungCondensed] PARTITION 1
				WITH ( WAIT_AT_LOW_PRIORITY ( MAX_DURATION = 1 MINUTES, ABORT_AFTER_WAIT = BLOCKERS ));  
		COMMIT
		BEGIN TRAN
			--Anyone who tries to query the table after the switch has happened and before
			--the transaction commits will be blocked: we've got a schema mod lock on the table

			--cycle out Current RCLadderRungCondensed
			ALTER TABLE [Condensed].[condensed].[RCLadderRungCondensed] SWITCH PARTITION 1 TO [Condensed].[old].[RCLadderRungCondensed] PARTITION 1
				WITH ( WAIT_AT_LOW_PRIORITY ( MAX_DURATION = 1 MINUTES, ABORT_AFTER_WAIT = BLOCKERS ));  

			--Cycle in New RCLadderRungCondensed
			ALTER TABLE [Condensed].[new].[RCLadderRungCondensed] SWITCH PARTITION 1 TO [Condensed].[condensed].[RCLadderRungCondensed] PARTITION 1
				WITH ( WAIT_AT_LOW_PRIORITY ( MAX_DURATION = 1 MINUTES, ABORT_AFTER_WAIT = BLOCKERS ));

			-- Cycle Old to New
			ALTER TABLE [Condensed].[old].[RCLadderRungCondensed] SWITCH PARTITION 1 TO [Condensed].[new].[RCLadderRungCondensed] PARTITION 1
				WITH ( WAIT_AT_LOW_PRIORITY ( MAX_DURATION = 1 MINUTES, ABORT_AFTER_WAIT = BLOCKERS ));  
		COMMIT		
		BEGIN TRAN
			--Anyone who tries to query the table after the switch has happened and before
			--the transaction commits will be blocked: we've got a schema mod lock on the table

			--cycle out Current OrgRCLadderRungCondensed
			ALTER TABLE [Condensed].[condensed].[OrgRCLadderRungCondensed] SWITCH PARTITION 1 TO [Condensed].[old].[OrgRCLadderRungCondensed] PARTITION 1
				WITH ( WAIT_AT_LOW_PRIORITY ( MAX_DURATION = 1 MINUTES, ABORT_AFTER_WAIT = BLOCKERS ));  

			--Cycle in New OrgRCLadderRungCondensed
			ALTER TABLE [Condensed].[new].[OrgRCLadderRungCondensed] SWITCH PARTITION 1 TO [Condensed].[condensed].[OrgRCLadderRungCondensed] PARTITION 1
				WITH ( WAIT_AT_LOW_PRIORITY ( MAX_DURATION = 1 MINUTES, ABORT_AFTER_WAIT = BLOCKERS ));

			-- Cycle Old to New
			ALTER TABLE [Condensed].[old].[OrgRCLadderRungCondensed] SWITCH PARTITION 1 TO [Condensed].[new].[OrgRCLadderRungCondensed] PARTITION 1
				WITH ( WAIT_AT_LOW_PRIORITY ( MAX_DURATION = 1 MINUTES, ABORT_AFTER_WAIT = BLOCKERS ));  
		COMMIT	
	
		IF @bImportLog <> 0 --2021-03-04
		BEGIN
			SELECT @nvMsg = 'Executed [Condensed].[condensed].[uspLoadRCCondensedConsolidated]';
			EXECUTE [import].[uspOrganizationLog] 
				 @pbiSrcTableId = 0
				,@pnvSrcTable = '0'
				,@pbiDstTableId = 0
				,@pnvDstTable = '0'
				,@pnvMsg = @nvMsg
				,@pbiActivityLength = 0 
				,@pnvUserName = @nvUserName;
		END
	END
	ELSE
		SELECT 'No Dates on monitored tables have changed.';
END

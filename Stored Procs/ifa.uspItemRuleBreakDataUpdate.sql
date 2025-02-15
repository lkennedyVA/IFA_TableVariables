USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspItemRuleBreakDataUpdate
	CreatedBy: Larry Dugger
	Description: This procedure will update Item(s) 
		and insert/update RuleBreakData(s) tables

	Tables: [ifa].[Item] 
		,[ifa].[RuleBreakData]
	
	Procedures: [error].[uspLogErrorDetailInsertOut]
	Functions: [ifa].[ufnProcessMethodologyDeux]

	History:
		2017-02-07 - LBD - Created
		2017-06-03 - LBD - Modified, removed use of archive tables
		2019-10-30 - LBD - Modified, added in ItemActivity update 
			,could be a source of serious contention.
		2020-02-07 - LBD - Modified, use new function to grab ProcessMethodology 
		2020-02-09 - LBD - Modified, correct missues of OrgClientName to OrgClientId
		2020-04-17 - LBD - Adjusted to handle ItemActivity proceduralization
		2020-06-03 - LBD - Adjusted logging so it operates without locking (unless necessary)
		2020-06-12 - LBD - Removed more contention
		2020-09-13 - LBD - Replace [ifa].[ufnProcessMethodology] with
			[ifa].[ufnProcessMethodologyDeux]
		2025-01-09 - LXK - Replaced table variable with local temp table.
*****************************************************************************************/
ALTER   PROCEDURE [ifa].[uspItemRuleBreakDataUpdate](
	@ptblItemRuleBreakData [ifa].[ItemRuleBreakDataType] READONLY
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @tblItem [ifa].[ItemType]
		,@tblOL [ifa].[OrgListType];

/* drop table if exists #ItemTypeRuleBreakUpdate
create table #ItemTypeRuleBreakUpdate(
	[ItemId] [bigint] NULL,
	[ItemTypeId] [int] NULL,
	[ProcessId] [bigint] NULL,
	[PayerId] [bigint] NULL,
	[ItemKey] [nvarchar](25) NULL,
	[ClientItemId] [nvarchar](50) NULL,
	[CheckNumber] [nvarchar](50) NULL,
	[CheckAmount] [money] NULL,
	[CheckTypeId] [int] NULL,
	[ItemTypeDate] [datetime] NULL,
	[Fee] [money] NULL,
	[Amount] [money] NULL,
	[MICR] [nvarchar](255) NULL,
	[Scanned] [bit] NULL,
	[RuleBreak] [nvarchar](25) NULL,
	[RuleBreakResponse] [nvarchar](255) NULL,
	[ItemStatusId] [int] NULL,
	[ClientAcceptedId] [int] NULL,
	[OriginalPayerId] [int] NULL,
	[OriginalCheckTypeId] [int] NULL,
	[AcctChkNbrSwitch] [bit] NULL,
	[StatusFlag] [int] NULL,
	[DateActivated] [datetime2](7) NULL,
	[UserName] [nvarchar](100) NULL
);

drop table if exists #OrgListRuleBreakUpdate 
create table #OrgListRuleBreakUpdate(
	[LevelId] [nvarchar](25) NULL,
	[RelatedOrgId] [int] NULL,
	[OrgId] [int] NULL,
	[OrgCode] [nvarchar](25) NULL,
	[OrgName] [nvarchar](50) NULL,
	[ExternalCode] [nvarchar](50) NULL,
	[OrgDescr] [nvarchar](255) NULL,
	[OrgTypeId] [int] NULL,
	[Type] [nvarchar](50) NULL,
	[StatusFlag] [int] NULL,
	[DateActivated] [datetime2](7) NULL,
	[UserName] [nvarchar](100) NULL
); */
		
	drop table if exists #Item
	create table #Item(
		ItemId bigint
		,InsertedRuleBreak nvarchar(25)
		,InsertedDateActivated datetime2(7)
	);
	DECLARE @iLogLevel int = ISNULL(TRY_CONVERT(INT,[common].[ufnConfigValue](N'LogLevel [ifa].[uspItemRuleBreakDataUpdate]')),1)	--2019-02-23 LBD
		,@dtTimerDate datetime2(7) = SYSDATETIME()
		,@dtInitial datetime2(7) = SYSDATETIME() --used for complete time in procedure
		,@ncSchemaName nchar(20) = CONVERT(nchar(20),OBJECT_SCHEMA_NAME(@@PROCID))
		,@ncObjectName nchar(50) = CONVERT(nchar(50),OBJECT_NAME(@@PROCID))
		,@iOrgId int 
		,@iOrgDimensionId int = [common].[ufnDimension]('Organization')
		,@ncProcessKey NCHAR(25)
		,@iRuleBreakDataId int = 0
		,@iProcessMethodology int 
		,@iProcessTypeId int --2020-09-13
		--,@iOrgClientId int
		,@iStatusFlag int = 1
		,@iErrorDetailId int
		,@sSchemaName nvarchar(128) = OBJECT_SCHEMA_NAME(@@PROCID)
		,@iCurrentTransactionLevel int;

	SELECT TOP 1 @ncProcessKey = p.ProcessKey
		,@iOrgId = p.OrgId
		,@iProcessTypeId = p.ProcessTypeId
	FROM @ptblItemRuleBreakData tirbd 
	INNER JOIN [ifa].[Item] i on tirbd.ItemId = i.ItemId
	INNER JOIN [ifa].[Process] p on i.ProcessId = p.ProcessId;

	--SELECT @iProcessMethodology = ProcessMethodologyId FROM [ifa].[ufnProcessMethodology](@iOrgClientId,@iOrgId); --2020-09-13

	IF @iLogLevel > 0
	BEGIN
		INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
		VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Enter and Variable Set' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());  	
		SET @dtTimerDate = SYSDATETIME();
	END

	--UPDATES first
	BEGIN TRY
		UPDATE rbd 
			SET Code = tirbd.Code
				,[Message] = tirbd.[Message]
				,DateActivated = SYSDATETIME()
				,UserName = tirbd.UserName

		FROM [ifa].[RuleBreakData] rbd
		INNER JOIN @ptblItemRuleBreakData tirbd on rbd.ItemId = tirbd.ItemId
	END TRY
	BEGIN CATCH
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		THROW
	END CATCH;

	--NOW inserts
	BEGIN TRY
		INSERT INTO [ifa].[RuleBreakData]
		SELECT tirbd.ItemId
			,tirbd.Code
			,tirbd.[Message]
			,@iStatusFlag
			,SYSDATETIME()
			,tirbd.UserName 
		FROM @ptblItemRuleBreakData tirbd
		WHERE NOT EXISTS (SELECT 'X' FROM [ifa].[RuleBreakData] WHERE tirbd.ItemId = ItemId);
	END TRY
	BEGIN CATCH
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		THROW
	END CATCH;

	BEGIN TRY
		UPDATE i 
		SET RuleBreak = CASE WHEN ISNULL(tirbd.RuleBreak,N'') = N'' THEN i.RuleBreak ELSE tirbd.RuleBreak END
			,RuleBreakResponse = CASE WHEN ISNULL(tirbd.RuleBreakResponse,N'') = N'' THEN i.RuleBreakResponse ELSE tirbd.RuleBreakResponse END
			,DateActivated = SYSDATETIME()
			,UserName = tirbd.UserName
		OUTPUT deleted.ItemId
			,inserted.RuleBreak
			,inserted.DateActivated
		INTO #Item
		FROM [ifa].[Item] i
		INNER JOIN @ptblItemRuleBreakData tirbd on i.ItemId = tirbd.ItemId;
	END TRY
	BEGIN CATCH
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		THROW
	END CATCH;

	IF @iLogLevel > 1
	BEGIN
		INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
		VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Item and RuleBreak Upsert' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());  	
		SET @dtTimerDate = SYSDATETIME();
	END
	--PROVIDE what ItemActivityUpdate needs
	INSERT INTO @tblItem(ItemId,RuleBreak,DateActivated)
	SELECT ItemId,InsertedRuleBreak,InsertedDateActivated
	FROM #Item;
	--2020-09-13	
	INSERT INTO @tblOL (LevelId, RelatedOrgId, OrgId, OrgCode, OrgName, ExternalCode, OrgDescr, OrgTypeId, [Type], StatusFlag)
	SELECT LevelId, ChildId, OrgId, OrgCode, OrgName, ExternalCode, OrgDescr, TypeId, [Type], StatusFlag
	FROM [common].[ufnUpDimensionByOrgIdILTF](@iOrgId,@iOrgDimensionId); 

	SELECT @iProcessMethodology = ProcessMethodologyId
	FROM [ifa].[ufnProcessMethodologyDeux](@tblOL,@iProcessTypeId);

	--UPDATE ItemActivity via procedure
	EXECUTE [ifa].[uspItemActivityUpdate]
		@ptblItem = @tblItem
		,@piProcessMethodology = @iProcessMethodology
		,@pncProcessKey = @ncProcessKey
		,@pnvSrc = @ncObjectName;	--uspItemRuleBreakDataUpdate

	--Last Message uses @dtInitial
	IF  @iLogLevel > 0
		INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
		VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Exit' ,DATEDIFF(microsecond,@dtInitial,SYSDATETIME()),SYSDATETIME());

END

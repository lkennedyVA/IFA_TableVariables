USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: [condensed].[uspLoadDBEnum]
	Created By: Larry Dugger
	Descr: This procedure loads [new].[DBEnum] table
	Tables: [condensed].[DBEnum]
		,[new].[DBEnum]
		,[organization].[Org]
		,[organization].[OrgXref]
   
	Functions: [common].[ufnDownDimensionByOrgIdILTF]
		,[common].[ufnOrgCheckTypeXrefByOrgId]
		,[common].[ufnOrgIdTypeXrefByOrgId]

	Procedures:[condensed].[uspTruncateTable]

	History:
		2016-07-07 - LBD - Created
		2017-02-15 - LBD - Modified, loads 'New' table, then switches with Current
			via renaming methodology.
		2018-03-21 - LBD - Modified, to only include those organizations under 99999
		2018-08-16 - LBD - Modified, use switching instead of renaming
		2021-03-04 - CBS - Added call to import.uspOrganizationLog if @pbImportLog = 1.  
			By default, we do not log that the procedure was executed
*****************************************************************************************/
ALTER PROCEDURE [condensed].[zzzuspLoadDBEnum](
	@pbImportLog BIT = 0 --2021-03-04
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @DBEnums table (
		 OrgId int
		,[Value] nvarchar(255)
		,Code nvarchar(25)
		,Name nvarchar(50)
		,DateActivated datetime2(7) 
	);
	DECLARE @Orgs table (OrgId int primary key);
	DECLARE @bImportLog bit = @pbImportLog --2021-03-04
		,@nvMsg nvarchar(256) --2021-03-04
		,@iOrgId int
		,@iOrgDimensionId int = [common].[ufnDimension]('Organization');

	SELECT @iOrgId = o.OrgId
	FROM [organization].[Org] o
	INNER JOIN [organization].[OrgType] ot on o.OrgTypeId = ot.OrgTypeId 
	WHERE ot.Code = '0'
		AND o.Name = 'Valid Systems Inc';

	INSERT INTO @Orgs(OrgId)
	SELECT OrgId
	FROM [common].[ufnDownDimensionByOrgIdILTF](@iOrgId,@iOrgDimensionId)
	WHERE ISNULL(ExternalCode,'') <> '';

	INSERT INTO @DBEnums(OrgId,[Value],Code,Name,DateActivated)
	SELECT o.OrgId
		,'CheckType' as Value
		,x.CheckTypeCode as Code
		,x.CheckTypeName as Name
		,SYSDATETIME()
	FROM @Orgs o
	CROSS APPLY [common].[ufnOrgCheckTypeXrefByOrgId](o.OrgId) x;
	--WHERE x.StatusFlag BETWEEN 1 and 2;

	INSERT INTO @DBEnums(OrgId,[Value],Code,Name,DateActivated)
	SELECT o.OrgId
		,'IdType' as Value
		,x.IdTypeCode as Code
		,x.IdTypeName as Name
		,SYSDATETIME()
	FROM  @Orgs o
	CROSS APPLY [common].[ufnOrgIdTypeXrefByOrgId](o.OrgId) x;

	EXECUTE [condensed].[uspTruncateTable] @pnvTargetTable='[new].[DBEnum]'

	INSERT INTO [new].[DBEnum](OrgId,[Value],Code,Name,DateActivated)
	SELECT OrgId,[Value],Code,Name,DateActivated
	FROM @DBEnums;

	--NOW switch the tables, minimizing impact
	BEGIN TRAN
		--Anyone who tries to query the table after the switch has happened and before
		--the transaction commits will be blocked: we've got a schema mod lock on the table

		--cycle out Current DBEnum
		ALTER TABLE [Condensed].[condensed].[DBEnum] SWITCH PARTITION 1 TO [Condensed].[old].[DBEnum] PARTITION 1
			WITH ( WAIT_AT_LOW_PRIORITY ( MAX_DURATION = 1 MINUTES, ABORT_AFTER_WAIT = BLOCKERS ));  

		--Cycle in New DBEnum
		ALTER TABLE [Condensed].[new].[DBEnum] SWITCH PARTITION 1 TO [Condensed].[condensed].[DBEnum] PARTITION 1
			WITH ( WAIT_AT_LOW_PRIORITY ( MAX_DURATION = 1 MINUTES, ABORT_AFTER_WAIT = BLOCKERS ));

		-- Cycle Old to New
		ALTER TABLE [Condensed].[old].[DBEnum] SWITCH PARTITION 1 TO [Condensed].[new].[DBEnum] PARTITION 1
			WITH ( WAIT_AT_LOW_PRIORITY ( MAX_DURATION = 1 MINUTES, ABORT_AFTER_WAIT = BLOCKERS ));  
	COMMIT

	IF @bImportLog <> 0 --2021-03-04
	BEGIN
		SELECT @nvMsg = 'Executed [Condensed].[condensed].[uspLoadDBEnum]';
		EXECUTE [import].[uspOrganizationLog] 
			 @pbiSrcTableId = 0
			,@pnvSrcTable = '0'
			,@pbiDstTableId = 0
			,@pnvDstTable = '[condensed].[DBEnum]'
			,@pnvMsg = @nvMsg
			,@pbiActivityLength = 0 
			,@pnvUserName = 'System';
	END
END

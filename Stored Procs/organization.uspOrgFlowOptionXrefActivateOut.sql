USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspOrgFlowOptionXrefActivateOut
	CreatedBy: Larry Dugger
	Date: 2015-05-07
	Description: This procedure will activate a xref record
	Tables: [organization].[OrgFlowOptionXref]

	History:
		2015-05-07 - LBD - Created
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [organization].[uspOrgFlowOptionXrefActivateOut](
	 @pnvUserName NVARCHAR(100) = 'N/A'
	,@piOrgFlowOptionXrefId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @OrgFlowOptionXref table (
		 OrgFlowOptionXrefId int
		,OrgId int
		,FlowOptionId int
		,FlowOptionValue nvarchar(50)
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
	);
	DECLARE @iErrorDetailId INT
		,@iCurrentTransactionLevel INT
		,@sSchemaName nvarchar(128) = N'organization';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	BEGIN TRANSACTION
	BEGIN TRY
		UPDATE [organization].[OrgFlowOptionXref]
		SET StatusFlag = 1
			,DateActivated = SYSDATETIME()
			,UserName = @pnvUserName
		OUTPUT deleted.OrgFlowOptionXrefId
			,deleted.OrgId
			,deleted.FlowOptionId
			,deleted.FlowOptionValue
			,deleted.StatusFlag
			,deleted.DateActivated
			,deleted.UserName
		INTO @OrgFlowOptionXref
		WHERE OrgFlowOptionXrefId = @piOrgFlowOptionXrefId;
		--INSERT INTO [archive].[OrgFlowOptionXref](OrgFlowOptionXrefId
		--	,OrgId
		--	,FlowOptionId
		--	,FlowOptionValue
		--	,StatusFlag
		--	,DateActivated
		--	,UserName
		--	,DateArchived
		--)
		--SELECT OrgFlowOptionXrefId
		--	,OrgId
		--	,FlowOptionId
		--	,FlowOptionValue
		--	,StatusFlag
		--	,DateActivated
		--	,UserName
		--	,SYSDATETIME()
		--FROM @OrgFlowOptionXref;
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		SET @piOrgFlowOptionXrefId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
	END CATCH;
	IF @@TRANCOUNT > @iCurrentTransactionLevel
	BEGIN
		COMMIT TRANSACTION;
		SELECT @piOrgFlowOptionXrefId = OrgFlowOptionXrefId
		FROM @OrgFlowOptionXref;
	END
END

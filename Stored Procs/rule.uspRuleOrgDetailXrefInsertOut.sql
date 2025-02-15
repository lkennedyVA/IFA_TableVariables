USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspRuleOrgDetailXrefInsertOut
	CreatedBy: Larry Dugger
	Date: 2012-20-03
	Descr: This procedure will insert a new record
	Tables: [rule].[RuleOrgDetailXref]
   
	Functions: [error].[uspLogErrorDetailInsertOut]
	History:
		2012-20-03 - LBD - Created
		2016-05-26 - LBD - Modified, allowed setting Value to null
*****************************************************************************************/
ALTER PROCEDURE [rule].[uspRuleOrgDetailXrefInsertOut](
	 @piRuleOrgXrefId INT
	,@piRuleDetailXrefId INT
	,@piOrgCheckTypeXrefId INT
	,@pnvValue NVARCHAR(512)
	,@pbEnrollmentFlag BIT 
	,@piStatusFlag INT
	,@pnvUserName NVARCHAR(100) = 'N/A'
	,@piRuleOrgDetailXrefId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @RuleOrgDetailXref table (
		RuleOrgDetailXrefId int
		,RuleOrgXrefId int
		,RuleDetailXrefId int
		,OrgCheckTypeXrefId int
		,[Value] nvarchar(512)
		,EnrollmentFlag bit
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100));
	DECLARE @iErrorDetailId int
		,@iCurrentTransactionLevel int
		,@sSchemaName sysname;
	SET @sSchemaName =N'rule';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	BEGIN TRANSACTION
	BEGIN TRY
		INSERT INTO [rule].[RuleOrgDetailXref]
			OUTPUT inserted.RuleOrgDetailXrefId
				,inserted.RuleOrgXrefId
				,inserted.RuleDetailXrefId
				,inserted.OrgCheckTypeXrefId
				,inserted.[Value]
				,inserted.EnrollmentFlag
				,inserted.StatusFlag
				,inserted.DateActivated
				,inserted.UserName
			INTO @RuleOrgDetailXref
		SELECT @piRuleOrgXrefId
			,@piRuleDetailXrefId
			,@piOrgCheckTypeXrefId
			,CASE WHEN ISNULL(@pnvValue,N'NULL') = N'NULL' THEN NULL ELSE @pnvValue END --If 'NULL' leave empty
			,@pbEnrollmentFlag
			,@piStatusFlag
			,SYSDATETIME()
			,@pnvUserName; 
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		SET @piRuleOrgDetailXrefId = -1 * @iErrorDetailId; --return the errordetailid negative (indicates an error occurred)
	END CATCH;
	IF @@TRANCOUNT > @iCurrentTransactionLevel
	BEGIN
		COMMIT TRANSACTION;
		SELECT @piRuleOrgDetailXrefId = RuleOrgDetailXrefId
		FROM @RuleOrgDetailXref
	END
END

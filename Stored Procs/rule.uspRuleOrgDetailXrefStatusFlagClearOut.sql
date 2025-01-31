USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspRuleOrgDetailXrefStatusFlagClearOut
	CreatedBy: Larry Dugger
	Date: 2012-20-03
	Descr: This procedure will DeActivate the RuleOrgDetailXref (Clear StatusFlag)
	Tables: [rule].[RuleOrgDetailXref]
   
	Functions: [error].[uspLogErrorDetailInsertOut]
	History:
		2012-20-03 - LBD - Created
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [rule].[uspRuleOrgDetailXrefStatusFlagClearOut](
	 @pnvUserName NVARCHAR(100) = 'N/A'
	,@piRuleOrgDetailXrefID INT OUTPUT
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
	DECLARE @iErrorDetailId INT
		,@iCurrentTransactionLevel INT
		,@sSchemaName SYSNAME;
	SET @sSchemaName =N'rule';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			UPDATE [rule].[RuleOrgDetailXref]
			SET StatusFlag = 0
				,DateActivated = SYSDATETIME()
				,UserName = @pnvUserName
			OUTPUT deleted.RuleOrgDetailXrefId
				,deleted.RuleOrgXrefId
				,deleted.RuleDetailXrefId
				,deleted.OrgCheckTypeXrefId
				,deleted.[Value]
				,deleted.EnrollmentFlag
				,deleted.StatusFlag
				,deleted.DateActivated
				,deleted.UserName
			INTO @RuleOrgDetailXref
			WHERE RuleOrgDetailXrefId = @piRuleOrgDetailXrefId;
			----Anytime an update occurs we place an original copy in an archive table
			--INSERT INTO [archive].[RuleOrgDetailXref](RuleOrgDetailXrefId
			--,RuleOrgXrefId
			--,RuleDetailXrefId
			--,OrgCheckTypeXrefId
			--,Value
			--,EnrollmentFlag
			--,StatusFlag
			--,DateActivated
			--	,UserName
			--,DateArchived
			--) 
			--SELECT RuleOrgDetailXrefId
			--,RuleOrgXrefId
			--,RuleDetailXrefId
			--,OrgCheckTypeXrefId
			--,Value
			--,EnrollmentFlag
			--,StatusFlag
			--,DateActivated
			--	,UserName
			--,SYSDATETIME()
			--FROM @RuleOrgDetailXref
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
			SELECT @piRuleOrgDetailXrefID = RuleOrgDetailXrefId
			FROM @RuleOrgDetailXref;
		END
	END
END

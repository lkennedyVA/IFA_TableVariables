USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspRuleOrgXrefStatusFlagClearOut
	CreatedBy: Larry Dugger
	Date: 2012-20-03
	Descr: This procedure will DeActivate the RuleOrgXref (Clear StatusFlag)
	Tables: [rule].[RuleOrgXref]
   
	Functions: [error].[uspLogErrorDetailInsertOut]
	History:
		2012-20-03 - LBD - Created
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [rule].[uspRuleOrgXrefStatusFlagClearOut](
	 @pnvUserName NVARCHAR(100) = 'N/A'
	,@piRuleOrgXrefID INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @RuleOrgXref table (
		 RuleOrgXrefId int
		,RuleGroupId int
		,RuleId int
		,OrgId int
		,StatusFlag int
		,OverridableFlag bit
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
	);
	DECLARE @iErrorDetailId INT
		,@iCurrentTransactionLevel INT
		,@sSchemaName SYSNAME;
	SET @sSchemaName =N'rule';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			UPDATE [rule].[RuleOrgXref]
			SET StatusFlag = 0
				,DateActivated = SYSDATETIME()
				,UserName = @pnvUserName
			OUTPUT deleted.RuleOrgXrefId
				,deleted.RuleGroupId
				,deleted.RuleId
				,deleted.OrgId
				,deleted.StatusFlag
				,deleted.OverridableFlag
				,deleted.DateActivated
				,deleted.UserName
			INTO @RuleOrgXref
			WHERE RuleOrgXrefId = @piRuleOrgXrefId;
			----Anytime an update occurs we place an original copy in an archive table
			--INSERT INTO [archive].[RuleOrgXref](RuleOrgXrefId
			--,RuleGroupId
			--,RuleId
			--,OrgId
			--,StatusFlag
			--,OverridableFlag
			--,DateActivated
			--	,UserName
			--,DateArchived
			--) 
			--SELECT RuleOrgXrefId
			--,RuleGroupId
			--,RuleId
			--,OrgId
			--,StatusFlag
			--,OverridableFlag
			--,DateActivated
			--	,UserName
			--,SYSDATETIME()
			--FROM @RuleOrgXref
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			SET @piRuleOrgXrefId = -1 * @iErrorDetailId; --return the errordetailid negative (indicates an error occurred)
		END CATCH;
		IF @@TRANCOUNT > @iCurrentTransactionLevel
		BEGIN
			COMMIT TRANSACTION;
			SELECT @piRuleOrgXrefID = RuleOrgXrefId
			FROM @RuleOrgXref;
		END
	END
END

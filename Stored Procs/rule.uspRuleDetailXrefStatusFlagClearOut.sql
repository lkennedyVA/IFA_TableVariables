USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspRuleDetailXrefStatusFlagClearOut
	CreatedBy: Larry Dugger
	Date: 2012-03-20
	Descr: This procedure will DeActivate the RuleDetailXref (Clear StatusFlag)

	Tables: [rule].[RuleDetailXref]
   
	Functions: [error].[uspLogErrorDetailInsertOut]

	History:
		2012-03-20 - LBD - Created
		2016-05-26 - CBS - Modified, added Username
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [rule].[uspRuleDetailXrefStatusFlagClearOut](
	 @piRuleDetailXrefID INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @RuleDetailXref table (
		 RuleDetailXrefId int
		,RuleId int
		,RuleDetailId int
		,DetailLevelId int
		,StatusFlag int
		,DateActivated datetime
		,Username nvarchar(100)
	);
	DECLARE @iErrorDetailId int
		,@iCurrentTransactionLevel int
		,@sSchemaName sysname
		,@nvUsername nvarchar(100) = 'N/A';
	SET @sSchemaName =N'rule';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;

	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			UPDATE [rule].[RuleDetailXref]
			SET StatusFlag = 0
				,DateActivated = SYSDATETIME()
				,UserName = @nvUsername
			OUTPUT Deleted.RuleDetailXrefId
				,Deleted.RuleId
				,Deleted.RuleDetailId
				,Deleted.DetailLevelId
				,Deleted.StatusFlag
				,Deleted.DateActivated
				,Deleted.UserName
			INTO @RuleDetailXref
			WHERE RuleDetailXrefId = @piRuleDetailXrefId;
			----Anytime an update occurs we place an original copy in an archive table
			--INSERT INTO [archive].[RuleDetailXref](RuleDetailXrefId
			--	,RuleId
			--	,RuleDetailId
			--	,DetailLevelId
			--	,StatusFlag
			--	,DateActivated
			--	,UserName
			--	,DateArchived
			--) 
			--SELECT RuleDetailXrefId
			--	,RuleId
			--	,RuleDetailId
			--	,DetailLevelId
			--	,StatusFlag
			--	,DateActivated
			--	,UserName
			--	,SYSDATETIME()
			--FROM @RuleDetailXref
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
				ROLLBACK TRANSACTION;
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			SET @piRuleDetailXrefId = -1 * @iErrorDetailId; --return the errordetailid negative (indicates an error occurred)
		END CATCH;
		IF @@TRANCOUNT > @iCurrentTransactionLevel
		BEGIN
			COMMIT TRANSACTION;
			SELECT @piRuleDetailXrefID = RuleDetailXrefId
			FROM @RuleDetailXref;
		END
	END
END

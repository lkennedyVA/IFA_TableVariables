USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspRuleDetailStatusFlagClearOut
	CreatedBy: Larry Dugger
	Date: 03-20-2012
	Descr: This procedure will DeActivate the RuleDetail (Clear StatusFlag)

	Tables: [rule].[RuleDetail]
   
	Functions: [error].[uspLogErrorDetailInsertOut]

	History:
		2012-03-20 - LBD - Created
		2016-05-26 - CBS - Modified, added username
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [rule].[uspRuleDetailStatusFlagClearOut](
	 @piRuleDetailID INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @RuleDetail table (
		 RuleDetailId int
		,Code nvarchar(25)
		,[Name] nvarchar(50)
		,Descr nvarchar(255)
		,StatusFlag int
		,DateActivated datetime
		,Username nvarchar(100)
	);
	DECLARE @iErrorDetailId INT
		,@iCurrentTransactionLevel INT
		,@sSchemaName SYSNAME
		,@nvUsername nvarchar(100) = 'N/A';
	SET @sSchemaName = N'rule';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;

	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			UPDATE [rule].[RuleDetail]
			SET StatusFlag = 0
				,DateActivated = SYSDATETIME()
				,UserName = @nvUsername
			OUTPUT Deleted.RuleDetailId
				,Deleted.Code
				,Deleted.[Name]
				,Deleted.Descr
				,Deleted.StatusFlag
				,Deleted.DateActivated
				,Deleted.UserName
			INTO @RuleDetail
			WHERE RuleDetailId = @piRuleDetailId;
			----Anytime an update occurs we place an original copy in an archive table
			--INSERT INTO [archive].[RuleDetail](RuleDetailId
			--	,Code
			--	,Name
			--	,Descr
			--	,StatusFlag
			--	,DateActivated
			--	,UserName
			--	,DateArchived
			--) 
			--SELECT RuleDetailId
			--	,Code
			--	,Name
			--	,Descr
			--	,StatusFlag
			--	,DateActivated
			--	,Username
			--	,SYSDATETIME()
			--FROM @RuleDetail
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			SET @piRuleDetailId = -1 * @iErrorDetailId; --return the errordetailid negative (indicates an error occurred)
		END CATCH;
		IF @@TRANCOUNT > @iCurrentTransactionLevel
		BEGIN
			COMMIT TRANSACTION;
			SELECT @piRuleDetailID = RuleDetailId
			FROM @RuleDetail;
		END
	END
END

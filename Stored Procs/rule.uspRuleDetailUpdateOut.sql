USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspRuleDetailUpdateOut
	CreatedBy: Larry Dugger
	Date: 03-20-2012
	Descr: This procedure will update the RuleDetail, it will not update the StatusFlag

	Tables: [rule].[RuleDetail]
   
	Functions: [common].[uspLogErrorDetailInsertOut]

	History:
		2012-03-20 - LBD - Created
		2016-05-26 - CBS - Modified, added Username
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [rule].[uspRuleDetailUpdateOut](
	 @piRuleDetailID INT OUTPUT
	,@pnvCode NVARCHAR(25) = N''
	,@pnvName NVARCHAR(50) = N''
	,@pnvDescr NVARCHAR(255) = N''
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
	DECLARE @iErrorDetailId int
		,@iCurrentTransactionLevel int
		,@sSchemaName sysname
		,@nvUsername nvarchar(100) = 'N/A';
	SET @sSchemaName = N'rule';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	--Will Not update this checktype to a checktype already in use
	IF NOT EXISTS(SELECT 'X' 
					FROM [rule].[RuleDetail]
					WHERE RuleDetailID <> @piRuleDetailId
						AND Name = @pnvName)
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			UPDATE [rule].[RuleDetail]
			SET Code = CASE WHEN @pnvCode = N'' THEN Code ELSE @pnvCode END
				,[Name] = CASE WHEN @pnvName = N'' THEN [Name] ELSE @pnvName END
				,Descr = CASE WHEN @pnvDescr = N'' THEN Descr ELSE @pnvDescr END
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
			----Anytime an update occurs we place a copy in an archive table
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
	ELSE
		SELECT @piRuleDetailID = -3
END

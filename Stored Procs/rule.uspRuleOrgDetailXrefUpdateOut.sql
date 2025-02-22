USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspRuleOrgDetailXrefUpdateOut
	Created By: Larry Dugger
	Descr: This procedure will update the RuleOrgDetailXref, it will not update 
			the StatusFlag or the EnrollmentFlag

	Tables: [rule].[RuleOrgDetailXref]
   
	Functions: [common].[uspLogErrorDetailInsertOut]

	History:
		2012-20-03 - LBD - Created
		2012-06-14 - LBD - Added EnrollmentFlag, but will not update it
		2016-05-26 - LBD - Modified, allowed setting Value to null
		2017-06-03 - LBD - Modified, removed use of archive tables
		2020-01-16 - CBS - Modified, added @piStatusFlag with a default of -1
*****************************************************************************************/
ALTER PROCEDURE [rule].[uspRuleOrgDetailXrefUpdateOut](
	 @piRuleOrgDetailXrefID INT OUTPUT
	,@piRuleOrgXrefId INT = -1
	,@piRuleDetailXrefId INT = -1
	,@piOrgCheckTypeXrefId INT = -1
	,@pbEnrollmentFlag BIT
	,@pnvValue NVARCHAR(512) = N''
	,@pnvUserName NVARCHAR(100) = 'N/A'
	,@piStatusFlag INT = -1 --2020-01-16
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
		,UserName nvarchar(100)
	);
	DECLARE @iErrorDetailId INT
		,@iCurrentTransactionLevel INT
		,@sSchemaName SYSNAME;
	SET @sSchemaName =N'rule';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;

	--Will Not update this xref to an rule/org/detail/checktype already in use
	IF NOT EXISTS(SELECT 'X' 
				FROM [rule].[RuleOrgDetailXref]
				WHERE RuleOrgDetailXrefID <> @piRuleOrgDetailXrefId
					AND (ISNULL(@piRuleOrgXrefId,-1) = -1
					OR RuleOrgXrefId = @piRuleOrgXrefId)
					AND (ISNULL(@piRuleDetailXrefId,-1) =-1
					OR RuleDetailXrefId = @piRuleDetailXrefId)
					AND (ISNULL(@piOrgCheckTypeXrefId,-1) =-1
					OR OrgCheckTypeXrefId = @piOrgCheckTypeXrefId)
				AND EnrollmentFlag = @pbEnrollmentFlag
				)
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			UPDATE [rule].[RuleOrgDetailXref]
			SET RuleOrgXrefId = CASE WHEN @piRuleOrgXrefId = -1 THEN RuleOrgXrefId ELSE @piRuleOrgXrefId END
				,RuleDetailXrefId = CASE WHEN @piRuleDetailXrefId = -1 THEN RuleDetailXrefId ELSE @piRuleDetailXrefId END
				,OrgCheckTypeXrefId = CASE WHEN @piOrgCheckTypeXrefId = -1 THEN OrgCheckTypeXrefId ELSE @piOrgCheckTypeXrefId END
				,[Value] = CASE WHEN ISNULL(@pnvValue,N'') = N'' THEN [Value] ELSE CASE WHEN @pnvValue = N'NULL' THEN NULL ELSE @pnvValue END END
				,DateActivated = SYSDATETIME()
				,UserName = @pnvUserName
				,StatusFlag = CASE WHEN @piStatusFlag = -1 THEN StatusFlag ELSE @piStatusFlag END --2020-01-16
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
			----Anytime an update occurs we place a copy in an archive table
			--INSERT INTO [archive].[RuleOrgDetailXref](RuleOrgDetailXrefId
			--	,RuleOrgXrefId
			--	,RuleDetailXrefId
			--	,OrgCheckTypeXrefId
			--	,[Value]
			--	,EnrollmentFlag
			--	,StatusFlag
			--	,DateActivated
			--	,UserName
			--	,DateArchived
			--) 
			--SELECT RuleOrgDetailXrefId
			--	,RuleOrgXrefId
			--	,RuleDetailXrefId
			--	,OrgCheckTypeXrefId
			--	,[Value]
			--	,EnrollmentFlag
			--	,StatusFlag
			--	,DateActivated
			--	,CASE WHEN ISNULL(UserName,'') = '' THEN 'N/A' END --It may be empty
			--	,SYSDATETIME()
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
	ELSE
		SELECT @piRuleOrgDetailXrefID = -3
END

USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspRCLadderTopUpdateOut
	CreatedBy: Larry Dugger
	Date: 2015-11-12
	Descr: This procedure will update the RCLadderTop, it will not update StatusFlag
	Tables: [riskprocessing].[RCLadderTop]
   
	Functions: [common].[uspLogErrorDetailInsertOut]
	History:
		2015-11-12 - LBD - Created.
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [riskprocessing].[uspRCLadderTopUpdateOut](
	 @piRCLadderTopId INT OUTPUT
	,@piOrgXrefId INT = -1
	,@piRCId INT = -1
	,@piLadderTopXrefId INT = -1
	,@pnvCollectionName NVARCHAR(100) = N''
	,@piStatusFlag INT = -1
	,@pnvUserName NVARCHAR(100) = 'N/A'
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @RCLadderTop table (
		 RCLadderTopId int
		,RCId int
		,OrgXrefId int
		,LadderTopXrefId int
		,CollectionName nvarchar(100)
		,StatusFlag int
		,DateActivated datetime
		,UserName nvarchar(100)
	);
	DECLARE @iErrorDetailId INT
		,@iCurrentTransactionLevel INT
		,@sSchemaName SYSNAME;
	SET @sSchemaName = N'riskprocessing';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	--Will Not update this RCLadderTop to a RCLadderTop already in use
	IF NOT EXISTS(SELECT 'X' 
					FROM [riskprocessing].[RCLadderTop]
					WHERE RCLadderTopId <> @piRCLadderTopId
						AND OrgXrefId = @piOrgXrefId
						AND RCId = @piRCId
							AND LadderTopXrefId = @piLadderTopXrefId
					)
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			UPDATE [riskprocessing].[RCLadderTop]
			SET OrgXrefId = CASE WHEN @piOrgXrefId = -1 THEN OrgXrefId ELSE @piOrgXrefId END
				,RCId = CASE WHEN @piRCId = -1 THEN RCId ELSE @piRCId END
				,LadderTopXrefId = CASE WHEN @piLadderTopXrefId = -1 THEN LadderTopXrefId ELSE @piLadderTopXrefId END
				,CollectionName = CASE WHEN @pnvCollectionName = N'' THEN CollectionName ELSE @pnvCollectionName END
				,StatusFlag = CASE WHEN @piStatusFlag = -1 THEN StatusFlag ELSE @piStatusFlag END
				,DateActivated = SYSDATETIME()
			,UserName = @pnvUserName
			OUTPUT deleted.RCLadderTopId
				,deleted.RCId
				,deleted.OrgXrefId
				,deleted.LadderTopXrefId
				,deleted.CollectionName
				,deleted.StatusFlag
				,deleted.DateActivated
				,deleted.UserName
			INTO @RCLadderTop
			WHERE RCLadderTopId = @piRCLadderTopId;
			----Anytime an update occurs we place a copy in an archive table
			--INSERT INTO [archive].[RCLadderTop](RCLadderTopId
			--,RCId
			--,OrgXrefId
			--	,LadderTopXrefId
			--	,CollectionName
			--,StatusFlag
			--,DateActivated
			--,UserName
			--,DateArchived
			--) 
			--SELECT RCLadderTopId
			--,RCId
			--,OrgXrefId
			--	,LadderTopXrefId
			--	,CollectionName
			--,StatusFlag
			--,DateActivated
			--,UserName
			--,SYSDATETIME()
			--FROM @RCLadderTop
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			SET @piRCLadderTopId = -1 * @iErrorDetailId; --return the errordetailid negative (indicates an error occurred)
		END CATCH;
		IF @@TRANCOUNT > @iCurrentTransactionLevel
		BEGIN
			COMMIT TRANSACTION;
			SELECT @piRCLadderTopId = RCLadderTopId
			FROM @RCLadderTop;
		END
	END
	ELSE
		SELECT @piRCLadderTopId = -3
END

USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspRCLadderTopNeverActiveOut
	CreatedBy: Larry Dugger
	Date: 2015-11-12
	Descr: This procedure will set the StatusFlag to 3 'NeverActive'
	Tables: [riskprocessing].[RCLadderTop]
   
	Functions: [error].[uspLogErrorDetailInsertOut]
	History:
		2015-11-12 - LBD - Created.
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [riskprocessing].[uspRCLadderTopNeverActiveOut](
	 @piRCLadderTopId INT OUTPUT
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
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			UPDATE [riskprocessing].[RCLadderTop]
			SET StatusFlag = 3
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
			----Anytime an update occurs we place an original copy in an archive table
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
END

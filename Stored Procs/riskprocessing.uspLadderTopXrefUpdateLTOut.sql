USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspLadderTopXrefUpdateLTOut
	CreatedBy: Larry Dugger
	Date: 2015-11-12
	Descr: This procedure will update the LadderTopXref Children XRefs
	Tables: [riskprocessing].[LadderTopXref]
   
	Functions: [common].[uspLogErrorDetailInsertOut]
	History:
		2015-11-12 - LBD - Created.
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [riskprocessing].[uspLadderTopXrefUpdateLTOut](
	 @piLadderTopXrefID INT OUTPUT
	,@pnvLadderSuccessValue NVARCHAR(512) = N''
	,@piLadderSuccessLTXId INT = -1
	,@piLadderContinueLTXId INT 
	,@pnvUserName NVARCHAR(100) = 'N/A'
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @LadderTopXref table (
		 LadderTopXrefId int
		,LadderTopId int
		,LadderSuccessValue nvarchar(512)
		,LadderSuccessLTXId int
		,LadderContinueLTXId int
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
	);
	DECLARE @iErrorDetailId INT
		,@iCurrentTransactionLevel INT
		,@sSchemaName SYSNAME;
	SET @sSchemaName = N'riskprocessing';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
   
	BEGIN TRANSACTION
	BEGIN TRY
		UPDATE [riskprocessing].[LadderTopXref]
		SET LadderSuccessValue = CASE WHEN @pnvLadderSuccessValue = N'' THEN LadderSuccessValue ELSE @pnvLadderSuccessValue END
			,LadderSuccessLTXId = CASE WHEN @piLadderSuccessLTXId = -1 THEN LadderSuccessLTXId ELSE @piLadderSuccessLTXId END
			,LadderContinueLTXId = CASE WHEN @piLadderContinueLTXId = -1 THEN LadderContinueLTXId ELSE @piLadderContinueLTXId END
			,DateActivated = SYSDATETIME()
			,UserName = @pnvUserName
		OUTPUT deleted.LadderTopXrefId
			,deleted.LadderTopId
			,deleted.LadderSuccessValue
			,deleted.LadderSuccessLTXId
			,deleted.LadderContinueLTXId
			,deleted.StatusFlag
			,deleted.DateActivated
			,deleted.UserName
		INTO @LadderTopXref
		WHERE LadderTopXrefId = @piLadderTopXrefId;
		----Anytime an update occurs we place a copy in an archive table
		--INSERT INTO [archive].[LadderTopXref](LadderTopXrefId
		--	,LadderTopId
		--	,LadderSuccessValue
		--	,LadderSuccessLTXId
		--	,LadderContinueLTXId
		--	,StatusFlag
		--	,DateActivated
		--	,UserName
		--	,DateArchived
		--) 
		--SELECT LadderTopXrefId
		--	,LadderTopId
		--	,LadderSuccessValue
		--	,LadderSuccessLTXId
		--	,LadderContinueLTXId
		--	,StatusFlag
		--	,DateActivated
		--	,UserName
		--	,SYSDATETIME()
		--FROM @LadderTopXref
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		SET @piLadderTopXrefId = -1 * @iErrorDetailId; --return the errordetailid negative (indicates an error occurred)
	END CATCH;
	IF @@TRANCOUNT > @iCurrentTransactionLevel
	BEGIN
		COMMIT TRANSACTION;
		SELECT @piLadderTopXrefID = LadderTopXrefId
		FROM @LadderTopXref;
	END
END

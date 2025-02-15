USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspLadderDBProcessXrefUpdateOut
	CreatedBy: Larry Dugger
	Date: 2015-07-08
	Descr: This procedure will update the LadderDBProcessXref, it will not update StatusFlag
	Tables: [riskprocessing].[LadderDBProcessXref]
   
	Functions: [common].[uspLogErrorDetailInsertOut]
	History:
		2015-07-08 - LBD - Created, from Validbank
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [riskprocessing].[uspLadderDBProcessXrefUpdateOut](
	 @pnvTitle NVARCHAR(255) = N''
	,@piLadderId INT = -1
	,@piDBProcessId INT = -1
	,@pnvDBProcessSuccessValue NVARCHAR(512) = N''
	,@piDBProcessSuccessLDBPXId INT = -1
	,@piDBProcessContinueLDBPXId INT 
	,@pnvUserName NVARCHAR(100) = 'N/A'
	,@piLadderDBProcessXrefID INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @LadderDBProcessXref table (
		 LadderDBProcessXrefId int
		,LadderId int
		,DBProcessId int
		,DBProcessSuccessValue nvarchar(512)
		,DBProcessSuccessLDBPXId int
		,DBProcessContinueLDBPXId int
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
	);
	DECLARE @iErrorDetailId INT
		,@iCurrentTransactionLevel INT
		,@sSchemaName SYSNAME;
	SET @sSchemaName = N'riskprocessing';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	--Will Not update this LadderDBProcessXref to a LadderDBProcessXref already in use
	IF NOT EXISTS(SELECT 'X' 
					FROM [riskprocessing].[LadderDBProcessXref]
					WHERE LadderDBProcessXrefId <> @piLadderDBProcessXrefId
						AND Title = @pnvTitle
						AND LadderId = @piLadderId
						AND DBProcessId = @piDBProcessId
					)
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			UPDATE [riskprocessing].[LadderDBProcessXref]
			SET Title = CASE WHEN @pnvTitle = N'' THEN Title ELSE @pnvTitle END
				,LadderId = CASE WHEN @piLadderId = -1 THEN LadderId ELSE @piLadderId END
				,DBProcessId = CASE WHEN @piDBProcessId = -1 THEN DBProcessId ELSE @piDBProcessId END
				,DBProcessSuccessValue = CASE WHEN @pnvDBProcessSuccessValue = N'' THEN DBProcessSuccessValue ELSE @pnvDBProcessSuccessValue END
				,DBProcessSuccessLDBPXId = CASE WHEN @piDBProcessSuccessLDBPXId = -1 THEN DBProcessSuccessLDBPXId ELSE @piDBProcessSuccessLDBPXId END
				,DBProcessContinueLDBPXId = CASE WHEN @piDBProcessContinueLDBPXId = -1 THEN DBProcessContinueLDBPXId ELSE @piDBProcessContinueLDBPXId END
				,DateActivated = SYSDATETIME()
				,UserName = @pnvUserName
			OUTPUT deleted.LadderDBProcessXrefId
				,deleted.LadderId
				,deleted.DBProcessId
				,deleted.DBProcessSuccessValue
				,deleted.DBProcessSuccessLDBPXId
				,deleted.DBProcessContinueLDBPXId
				,deleted.StatusFlag
				,deleted.DateActivated
				,deleted.UserName
			INTO @LadderDBProcessXref
			WHERE LadderDBProcessXrefId = @piLadderDBProcessXrefId;
			----Anytime an update occurs we place a copy in an archive table
			--INSERT INTO [archive].[LadderDBProcessXref](LadderDBProcessXrefId
			--,LadderId
			--,DBProcessId
			--,DBProcessSuccessValue
			--,DBProcessSuccessLDBPXId
			--,DBProcessContinueLDBPXId
			--,StatusFlag
			--,DateActivated
			--,UserName
			--,DateArchived
			--) 
			--SELECT LadderDBProcessXrefId
			--,LadderId
			--,DBProcessId
			--,DBProcessSuccessValue
			--,DBProcessSuccessLDBPXId
			--,DBProcessContinueLDBPXId
			--,StatusFlag
			--,DateActivated
			--,UserName
			--,SYSDATETIME()
			--FROM @LadderDBProcessXref
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			SET @piLadderDBProcessXrefId = -1 * @iErrorDetailId; --return the errordetailid negative (indicates an error occurred)
		END CATCH;
		IF @@TRANCOUNT > @iCurrentTransactionLevel
		BEGIN
			COMMIT TRANSACTION;
			SELECT @piLadderDBProcessXrefID = LadderDBProcessXrefId
			FROM @LadderDBProcessXref;
		END
	END
	ELSE
		SELECT @piLadderDBProcessXrefID = -3
END

USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspClientAcceptedStatusFlagClearOut
	CreatedBy: Larry Dugger
	Date: 2015-08-04
	Descr: This procedure will DeActivate the ClientAccepted (Clear StatusFlag)
	Tables: [common].[ClientAccepted]
   
	Functions: [error].[uspLogErrorDetailInsertOut]
	History:
		2015-08-04 - LBD - Created
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [common].[uspClientAcceptedStatusFlagClearOut](
	 @pnvUserName NVARCHAR(100) = 'N/A'
	,@piClientAcceptedId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @ClientAccepted table (
		 ClientAcceptedId int
		,Code nvarchar(25)
		,[Name] nvarchar(50)
		,Descr nvarchar(255)
		,DisplayOrder int
		,StatusFlag int
		,DateActivated datetime2(7)		
		,UserName nvarchar(100)
	);
	DECLARE @iErrorDetailId INT
		,@iCurrentTransactionLevel INT
		,@sSchemaName nvarchar(128);
	SET @sSchemaName = N'common';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			UPDATE [common].[ClientAccepted]
			SET StatusFlag = 0
				,DateActivated = SYSDATETIME()
				,UserName = @pnvUserName
			OUTPUT deleted.ClientAcceptedId
				,deleted.Code
				,deleted.[Name]
				,deleted.Descr
				,deleted.DisplayOrder
				,deleted.StatusFlag
				,deleted.DateActivated
				,deleted.UserName
			INTO @ClientAccepted
			WHERE ClientAcceptedId = @piClientAcceptedId;
			----Anytime an update occurs we place an original copy in an archive table
			--INSERT INTO [archive].[ClientAccepted](ClientAcceptedId
			--,Code
			--,Name
			--,Descr
			--,DisplayOrder
			--,StatusFlag
			--,DateActivated
			--	,UserName
			--,DateArchived
			--) 
			--SELECT ClientAcceptedId
			--,Code
			--,Name
			--,Descr
			--,DisplayOrder
			--,StatusFlag
			--,DateActivated
			--	,UserName
			--,SYSDATETIME()
			--FROM @ClientAccepted
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			SET @piClientAcceptedId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
		END CATCH;
		IF @@TRANCOUNT > @iCurrentTransactionLevel
		BEGIN
			COMMIT TRANSACTION;
			SELECT @piClientAcceptedId = ClientAcceptedId
			FROM @ClientAccepted;
		END
	END
END

USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspRCDeactivateOut
	CreatedBy: Larry Dugger
	Date: 2015-07-08
	Descr: This procedure will DeActivate the RC (Clear StatusFlag)
	Tables: [riskprocessing].[RC]
   
	Functions: [error].[uspLogErrorDetailInsertOut]
	History:
		2015-07-08 - LBD - Created, from Validbank
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [riskprocessing].[uspRCDeactivateOut](
	@piRCId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @RC table (
		 RCId int
		,Code nvarchar(25)
		,[Name] nvarchar(50)
		,Descr nvarchar(255)
		,StatusFlag int
		,DateActivated datetime
		,UserName nvarchar(100)
	);
	DECLARE @iErrorDetailId INT
		,@iCurrentTransactionLevel INT
		,@sSchemaName SYSNAME;
	SET @sSchemaName = N'riskcontrol';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			UPDATE [riskprocessing].[RC]
			SET StatusFlag = 0
				,DateActivated = SYSDATETIME()
			OUTPUT deleted.RCId
				,deleted.Code
				,deleted.[Name]
				,deleted.Descr
				,deleted.StatusFlag
				,deleted.DateActivated
				,deleted.UserName
			INTO @RC
			WHERE RCId = @piRCId;
			----Anytime an update occurs we place an original copy in an archive table
			--INSERT INTO [archive].[RC](RCId
			--,Code
			--,Name
			--,Descr
			--,StatusFlag
			--,DateActivated
			--,DateArchived
			--	,UserName
			--) 
			--SELECT RCId
			--,Code
			--,Name
			--,Descr
			--,StatusFlag
			--,DateActivated
			--	,UserName
			--,SYSDATETIME()
			--FROM @RC
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			SET @piRCId = -1 * @iErrorDetailId; --return the errordetailid negative (indicates an error occurred)
		END CATCH;
		IF @@TRANCOUNT > @iCurrentTransactionLevel
		BEGIN
			COMMIT TRANSACTION;
			SELECT @piRCId = RCId
			FROM @RC;
		END
	END
END

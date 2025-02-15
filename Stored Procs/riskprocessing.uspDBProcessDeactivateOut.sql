USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspDBProcessDeactivateOut
	CreatedBy: Larry Dugger
	Date: 2015-07-08
	Descr: This procedure will DeActivate the DBProcess (Clear StatusFlag)
	Tables: [riskprocessing].[DBProcess]
   
	Functions: [error].[uspLogErrorDetailInsertOut]
	History:
		2015-07-08 - LBD - Created, from Validbank
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [riskprocessing].[uspDBProcessDeactivateOut](
	 @pnvUserName NVARCHAR(100) = 'N/A'
	,@piDBProcessId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @DBProcess table (
		DBProcessId int
		,Code nvarchar(25)
		,[Name] nvarchar(50)
		,Descr nvarchar(255)
		,ObjectFullName nvarchar(255)
		,RetrievalType nvarchar(25)
		,RetrievalCode nvarchar(25)
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
			UPDATE [riskprocessing].[DBProcess]
			SET StatusFlag = 0
				,DateActivated = SYSDATETIME()
				,UserName = @pnvUserName
			OUTPUT deleted.DBProcessId
				,deleted.Code
				,deleted.[Name]
				,deleted.Descr
				,deleted.ObjectFullName
				,deleted.RetrievalType
				,deleted.RetrievalCode
				,deleted.StatusFlag
				,deleted.DateActivated
				,deleted.UserName
			INTO @DBProcess
			WHERE DBProcessId = @piDBProcessId;
			----Anytime an update occurs we place an original copy in an archive table
			--INSERT INTO [archive].[DBProcess](DBProcessId
			--,Code
			--,Name
			--,Descr
			--	,ObjectFullName
			--	,RetrievalType
			--	,RetrievalCode
			--,StatusFlag
			--,DateActivated
			--,UserName
			--,DateArchived
			--) 
			--SELECT DBProcessId
			--,Code
			--,Name
			--,Descr
			--	,ObjectFullName
			--	,RetrievalType
			--	,RetrievalCode
			--,StatusFlag
			--,DateActivated
			--,UserName
			--,SYSDATETIME()
			--FROM @DBProcess
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			SET @piDBProcessId = -1 * @iErrorDetailId; --return the errordetailid negative (indicates an error occurred)
		END CATCH;
		IF @@TRANCOUNT > @iCurrentTransactionLevel
		BEGIN
			COMMIT TRANSACTION;
			SELECT @piDBProcessId = DBProcessId
			FROM @DBProcess;
		END
	END
END

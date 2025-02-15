USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspDBProcessUpdateOut
	CreatedBy: Larry Dugger
	Date: 2015-07-08
	Descr: This procedure will update the DBProcess, it will not update StatusFlag
	Tables: [riskprocessing].[DBProcess]
   
	Functions: [common].[uspLogErrorDetailInsertOut]
	History:
		2015-07-08 - LBD - Created, from Validbank
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [riskprocessing].[uspDBProcessUpdateOut](
	 @pnvCode NVARCHAR(25) = N''
	,@pnvName NVARCHAR(128) = N''
	,@pnvDescr NVARCHAR(255) = N''
	,@pnvObjectFullName NVARCHAR(25) = N''
	,@pnvRetrievalType NVARCHAR(25) = N''
	,@pnvRetrievalCode NVARCHAR(25) = N''
	,@pnvUserName NVARCHAR(100) = 'N/A'
	,@piDBProcessID INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @DBProcess table (
		 DBProcessId int
		,Code nvarchar(25)
		,[Name] nvarchar(128)
		,Descr nvarchar(255)
		,ObjectFullName nvarchar(255)
		,RetrievalType nvarchar(25)
		,RetrievalCode nvarchar(25)
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
	);
	DECLARE @iErrorDetailId INT
		,@iCurrentTransactionLevel INT
		,@sSchemaName SYSNAME;
	SET @sSchemaName = N'riskprocessing';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	--Will Not update this DBProcess to a DBProcess already in use
	IF NOT EXISTS(SELECT 'X' 
					FROM [riskprocessing].[DBProcess]
					WHERE DBProcessId <> @piDBProcessId
						AND ([Name] = @pnvName
						OR Code = @pnvCode)
					)
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			UPDATE [riskprocessing].[DBProcess]
			SET Code = CASE WHEN @pnvCode = N'' THEN Code ELSE @pnvCode END
				,[Name] = CASE WHEN @pnvName = N'' THEN [Name] ELSE @pnvName END
				,Descr = CASE WHEN @pnvDescr = N'' THEN Descr ELSE @pnvDescr END
				,ObjectFullName = CASE WHEN @pnvObjectFullName = N'' THEN ObjectFullName ELSE @pnvObjectFullName END
				,RetrievalType = CASE WHEN @pnvRetrievalType = N'' THEN RetrievalType ELSE @pnvRetrievalType END
				,RetrievalCode = CASE WHEN @pnvRetrievalCode = N'' THEN RetrievalCode ELSE @pnvRetrievalCode END
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
			----Anytime an update occurs we place a copy in an archive table
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
			SELECT @piDBProcessID = DBProcessId
			FROM @DBProcess;
		END
	END
	ELSE
		SELECT @piDBProcessID = -3
END

USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: [import].[uspKEYExceptionInsert]
	Created By: Chris and Lee
	Date: 2017-08-18
	Description: This procedure will insert a new records into
	Tables: [import].[BulkException]
		,import].[ExceptionType]
		,[import].[KEYException]
	Functions: [import].[ufnKEYExceptionList]
		,[import].[uspProcessKEYException]
	History:
		2023-05-12 - LSW - VALID-978: Created, based upon uspPNCExceptionInsert
		2025-01-14 - LXK - Replaced table variables with local temp tables
*****************************************************************************************/
ALTER   PROCEDURE [import].[uspKEYExceptionInsert](
	@pbiFileId BIGINT 
	,@pnvUserName NVARCHAR(100) 
)
AS
BEGIN
	SET NOCOUNT ON;
	drop table if exists #KEYExceptionInsertBulk
	create table #KEYExceptionInsertBulk(
		BulkExceptionId bigint
	);
	drop table if exists #KEYExceptionInsert
	create table #KEYExceptionInsert(
		 BulkExceptionId bigint primary key
		,ClientItemId nvarchar(50)
		,ItemKey nvarchar(25)
		,CustomerAccountNumber nvarchar(50)
		,DateOfDeposit date
		,ItemAmount money
		,Fee money
		,ExceptionTypeId int
		,Processed bit
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
	);
	DECLARE @iErrorDetailId int
		,@iCurrentTransactionLevel int
		,@sSchemaName nvarchar(128) = N'import';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	INSERT INTO #KEYExceptionInsert(
		BulkExceptionId
		,ClientItemId
		,ItemKey
		,CustomerAccountNumber
		,DateOfDeposit
		,ItemAmount 
		,Fee 
		,ExceptionTypeId
		,Processed
		,DateActivated
		,UserName
	)
	SELECT be.BulkExceptionId
		,pel.ClientItemId
		,pel.ItemKey
		,pel.CustomerAccountNumber
		,pel.DateOfDeposit
		,pel.ItemAmount 
		,pel.Fee 
		,et.ExceptionTypeId
		,0 AS Processed
		,SYSDATETIME() AS DateActivated
		,@pnvUsername AS UserName
	FROM [import].[BulkException] be
	CROSS APPLY [import].[ufnKEYExceptionList](be.FileRow,',',1) pel
	INNER JOIN [import].[ExceptionType] et ON pel.ExceptionTypeCode = et.Code
	WHERE FileId = @pbiFileId	--just the file indicated
		AND RowType = 'E'		--just pickup the exception rows, no headers or tails
		AND Processed = 0;		--only those we haven't inserted
	IF EXISTS (SELECT 'X' FROM #KEYExceptionInsert)
	BEGIN
		BEGIN TRY
			INSERT INTO [import].[KEYException](
				 BulkExceptionId
				,ClientItemId
				,ItemKey
				,CustomerAccountNumber
				,DateOfDeposit
				,ItemAmount 
				,Fee 
				,ExceptionTypeId
				,Processed
				,StatusFlag
				,DateActivated
				,UserName
			)
			OUTPUT inserted.BulkExceptionId
			INTO #KEYExceptionInsertBulk
			SELECT BulkExceptionId
				,ClientItemId
				,ItemKey
				,CustomerAccountNumber
				,DateOfDeposit
				,ItemAmount 
				,Fee 
				,ExceptionTypeId
				,Processed
				,0
				,DateActivated
				,UserName
			FROM #KEYExceptionInsert
			ORDER BY BulkExceptionId;

			UPDATE be
				SET be.Processed = 1
			FROM [import].[BulkException] be
			INNER JOIN #KEYExceptionInsertBulk tbe on be.BulkExceptionId = tbe.BulkExceptionId;
		END TRY
		BEGIN CATCH
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			RETURN
		END CATCH;
		EXECUTE [import].[uspProcessKEYException] @pnvUserName=@pnvUserName; 
	END
END

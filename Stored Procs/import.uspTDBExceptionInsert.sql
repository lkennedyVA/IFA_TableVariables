USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspTDBExceptionInsert
	CreatedBy: Larry Dugger
	Description: This procedure will insert a new records into
	Tables: [import].[BulkException]
		,[import].[ExceptionType]
		,[import].[TDBException]
	Functions: [import].[ufnTDBExceptionList]
		,[import].[uspProcessTDBException]
	History:
		2020-06-04 - LBD - Created, commented piece that updates 'Item' until approved.
		2025-01-14 - LXK - Replaced table variables with local temp tables
*****************************************************************************************/
ALTER   PROCEDURE [import].[uspTDBExceptionInsert](
	 @pbiFileId BIGINT
	,@pnvUserName NVARCHAR(100)
)
AS
BEGIN
	SET NOCOUNT ON;
	drop table if exists #TDBExceptionInsertBulk
	create table #TDBExceptionInsertBulk(
		BulkExceptionId bigint
	);
	drop table if exists #TDBExceptionInsert
	create table #TDBExceptionInsert(
		 BulkExceptionId bigint primary key
		,ProcessKey nvarchar(25)
		,ItemKey nvarchar(25)
		,ReferenceDate date
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
	INSERT INTO #TDBExceptionInsert(BulkExceptionId,ProcessKey,ItemKey,ReferenceDate,ExceptionTypeId,Processed,DateActivated,UserName)
	SELECT BulkExceptionId,pel.ProcessKey,pel.ItemKey,pel.ReferenceDate,et.ExceptionTypeId,0,SYSDATETIME(),@pnvUsername
	FROM [import].[BulkException] be
	CROSS APPLY [import].[ufnTDBExceptionList](be.FileRow,',',1) pel
	INNER JOIN [import].[ExceptionType] et ON pel.ExceptionTypeCode = et.Code
	WHERE FileId = @pbiFileId	--just the file indicated
		AND RowType = 'E'		--just pickup the exception rows, no headers or tails
		AND Processed = 0;		--only those we haven't inserted
	IF EXISTS (SELECT 'X' FROM #TDBExceptionInsert)
	BEGIN
		BEGIN TRY
			INSERT INTO [import].[TDBException](BulkExceptionId, ProcessKey, ItemKey, ReferenceDate, ExceptionTypeId, Processed, StatusFlag, DateActivated, UserName)
				OUTPUT inserted.BulkExceptionId
				INTO #TDBExceptionInsertBulk
			SELECT BulkExceptionId,ProcessKey,ItemKey,ReferenceDate,ExceptionTypeId,Processed,0,DateActivated,UserName
			FROM #TDBExceptionInsert
			ORDER BY BulkExceptionId;
			UPDATE be
				SET be.Processed = 1
			FROM [import].[BulkException] be
			INNER JOIN #TDBExceptionInsertBulk tbe on be.BulkExceptionId = tbe.BulkExceptionId;
		END TRY
		BEGIN CATCH
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			RETURN
		END CATCH;
		--EXECUTE [import].[uspProcessTDBException] @pnvUserName=@pnvUserName; 
	END
END

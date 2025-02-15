USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspPNCExceptionInsert
	CreatedBy: Larry Dugger
	Date: 2017-08-18
	Description: This procedure will insert a new records into
	Tables: [import].[BulkException]
		,import].[ExceptionType]
		,[import].[PNCException]
	Functions: [import].[ufnPNCExceptionList]
		,[import].[uspProcessPNCException]
	History:
		2017-08-18 - LBD - Created, commented piece that updates 'Item' until approved.
		2017-08-21 - LBD - Modified, activated uspProcessPNCException
		2017-10-25 - LBD - Modified, added StatusFlag
		2025-01-14 - LXK - Replaced table variables with local temp tables
*****************************************************************************************/
ALTER PROCEDURE [import].[uspPNCExceptionInsert](
	 @pbiFileId BIGINT
	,@pnvUserName NVARCHAR(100)
)
AS
BEGIN
	SET NOCOUNT ON;
	drop table if exists #PNCExceptionInsertBulk
	create table #PNCExceptionInsertBulk(
		BulkExceptionId bigint
	);
	drop table if exists #PNCExceptionInsert
	create table #PNCExceptionInsert(
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
	INSERT INTO #PNCExceptionInsert(BulkExceptionId,ProcessKey,ItemKey,ReferenceDate,ExceptionTypeId,Processed,DateActivated,UserName)
	SELECT BulkExceptionId,pel.ProcessKey,pel.ItemKey,pel.ReferenceDate,et.ExceptionTypeId,0,SYSDATETIME(),@pnvUsername
	FROM [import].[BulkException] be
	CROSS APPLY [import].[ufnPNCExceptionList](be.FileRow,',',1) pel
	INNER JOIN [import].[ExceptionType] et ON pel.ExceptionTypeCode = et.Code
	WHERE FileId = @pbiFileId	--just the file indicated
		AND RowType = 'E'		--just pickup the exception rows, no headers or tails
		AND Processed = 0;		--only those we haven't inserted
	IF EXISTS (SELECT 'X' FROM #PNCExceptionInsert)
	BEGIN
		BEGIN TRY
			INSERT INTO [import].[PNCException](BulkExceptionId, ProcessKey, ItemKey, ReferenceDate, ExceptionTypeId, Processed, StatusFlag, DateActivated, UserName)
				OUTPUT inserted.BulkExceptionId
				INTO #PNCExceptionInsertBulk
			SELECT BulkExceptionId,ProcessKey,ItemKey,ReferenceDate,ExceptionTypeId,Processed,0,DateActivated,UserName
			FROM #PNCExceptionInsert
			ORDER BY BulkExceptionId;
			UPDATE be
				SET be.Processed = 1
			FROM [import].[BulkException] be
			INNER JOIN #PNCExceptionInsertBulk tbe on be.BulkExceptionId = tbe.BulkExceptionId;
		END TRY
		BEGIN CATCH
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			RETURN
		END CATCH;
		EXECUTE [import].[uspProcessPNCException] @pnvUserName=@pnvUserName; 
	END
END

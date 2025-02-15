USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: [import].[uspTFBExceptionInsert]
	Created By: Chris Sharp
	Description: This procedure will insert a new records into

	Tables: [import].[BulkException]
		,import].[ExceptionType]
		,[import].[TFBException]

	Procedures: [import].[uspProcessTFBException]

	Functions: [import].[ufnTFBExceptionList]

	History:
		2023-09-05 - CBS - VALID-1230: Created, based upon uspPNCExceptionInsert
		2025-01-14 - LXK - Replaced table variables with local temp tables
*****************************************************************************************/
ALTER   PROCEDURE [import].[uspTFBExceptionInsert](
	 @pbiFileId BIGINT
	,@pnvUserName NVARCHAR(100)
)
AS
BEGIN
	SET NOCOUNT ON;
	crop table if exists #TFBExceptionInsertBulk
	create table #TFBExceptionInsertBulk(
		BulkExceptionId bigint
	);
	drop table if exists #TFBExceptionInsert
	create table #TFBExceptionInsert(
		 BulkExceptionId bigint primary key
		,ProcessKey NVARCHAR(25)
		,ItemKey NVARCHAR(25)
		,ReferenceDate DATE
		,ExceptionTypeId int
		,Processed bit
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
	);
	DECLARE @iErrorDetailId int
		,@sSchemaName nvarchar(128) = N'import';

	INSERT INTO #TFBExceptionInsert(
		 BulkExceptionId
		,ProcessKey
		,ItemKey 
		,ReferenceDate 
		,ExceptionTypeId 
		,Processed 
		,StatusFlag 
		,DateActivated 
		,UserName 
	)
	SELECT be.BulkExceptionId
		,pel.ProcessKey
		,pel.ItemKey
		,pel.ReferenceDate
		,et.ExceptionTypeId
		,0 AS Processed
		,1 AS StatusFlag
		,SYSDATETIME() AS DateActivated
		,@pnvUsername AS UserName
	FROM [import].[BulkException] be
	CROSS APPLY [import].[ufnTFBExceptionList](be.FileRow,',',1) pel
	INNER JOIN [import].[ExceptionType] et ON pel.ExceptionTypeCode = et.Code
	WHERE FileId = @pbiFileId	--just the file indicated
		AND RowType = 'E'		--just pickup the exception rows, no headers or tails
		AND Processed = 0;		--only those we haven't inserted
	IF EXISTS (SELECT 'X' FROM #TFBExceptionInsert)
	BEGIN
		BEGIN TRY
			INSERT INTO [import].[TFBException](
				 BulkExceptionId
				,ProcessKey
				,ItemKey
				,ReferenceDate
				,ExceptionTypeId
				,Processed
				,StatusFlag
				,DateActivated
				,UserName
			)
			OUTPUT inserted.BulkExceptionId
			INTO #TFBExceptionInsertBulk
			SELECT BulkExceptionId
				,ProcessKey
				,ItemKey
				,ReferenceDate
				,ExceptionTypeId
				,Processed
				,0 AS StatusFlag 
				,DateActivated
				,UserName
			FROM #TFBExceptionInsert
			ORDER BY BulkExceptionId;

			UPDATE be
			SET be.Processed = 1
			FROM [import].[BulkException] be
			INNER JOIN #TFBExceptionInsertBulk tbe 
				ON be.BulkExceptionId = tbe.BulkExceptionId;
		END TRY
		BEGIN CATCH
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			RETURN
		END CATCH;
		EXECUTE [import].[uspProcessTFBException] @pnvUserName=@pnvUserName; 
	END
END

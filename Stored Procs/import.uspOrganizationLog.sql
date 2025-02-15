USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: [import].[uspOrganizationLog]
	Created By: Chris Sharp
	Description: This procedure will process all of the unprocessed records
		
	Tables: [import].[Log]
		
	Procedures: [error].[uspLogErrorDetailInsertOut]

	History:
		2021-01-28 - CBS - Created
*****************************************************************************************/
ALTER   PROCEDURE [import].[uspOrganizationLog](
	 @pbiSrcTableId BIGINT
	,@pnvSrcTable NVARCHAR(128)
	,@pbiDstTableId BIGINT
	,@pnvDstTable NVARCHAR(128)
	,@pnvMsg NVARCHAR(256)
	,@pbiActivityLength BIGINT
	,@pnvUserName NVARCHAR(100)
)
AS 
BEGIN
	SET NOCOUNT ON;
	DECLARE @biSrcTableId BIGINT = @pbiSrcTableId
		,@nvSrcTable NVARCHAR(128) = @pnvSrcTable
		,@biDstTableId BIGINT = @pbiDstTableId
		,@nvDstTable NVARCHAR(128) = @pnvDstTable
		,@nvMsg NVARCHAR(256) = @pnvMsg
		,@biActivityLength BIGINT = @pbiActivityLength
		,@nvUserName NVARCHAR(100) = @pnvUserName
		,@iErrorDetailId int = 0
		,@sSchemaName nvarchar(128) = OBJECT_SCHEMA_NAME(@@PROCID)

	BEGIN TRY
		INSERT INTO	[import].[Log](
				 SrcTableId
				,SrcTable
				,DstTableId
				,DstTable
				,Msg
				,ActivityLength
				,DateActivated
				,UserName
			)
		SELECT @biSrcTableId 
			,@nvSrcTable 
			,@biDstTableId 
			,@nvDstTable
			,@nvMsg
			,@biActivityLength
			,SYSDATETIME()
			,@nvUserName
	END TRY
	BEGIN CATCH
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		THROW
	END CATCH
END

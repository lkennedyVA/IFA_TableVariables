USE [IFA]
GO
/****** Object:  StoredProcedure [command].[uspCommentInsertOut]    Script Date: 1/2/2025 6:03:51 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspCommentInsertOut
	Created By: Chris Sharp
	Description: This procedure will insert a Comment to be associated with an Action 
		record

	Tables: [command].[Comment]

	Procedures: [error].[uspLogErrorDetailUpdateOut]
   
	History:
		2018-03-01 - CBS - Created
*****************************************************************************************/
ALTER   PROCEDURE [command].[uspCommentInsertOut](
	 @pnvComment NVARCHAR(512)  
	,@pnvUserName NVARCHAR(100)
	,@pbiCommentId BIGINT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @tblComment TABLE (
		 CommentId bigint
	);
	DECLARE @iErrorDetailId int
		,@sSchemaName sysname = N'command';

	BEGIN TRY
		INSERT INTO [command].[Comment] (
			 Comment
			,StatusFlag
			,DateActivated
			,UserName
		)
		OUTPUT inserted.CommentId 
		INTO @tblComment
		SELECT @pnvComment
			,1 AS StatusFlag
			,SYSDATETIME() AS DateActivated
			,@pnvUserName;

		SELECT @pbiCommentId = CommentId 
		FROM @tblComment;

	END TRY
	BEGIN CATCH
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		SET @pbiCommentId = -1 * @iErrorDetailId; --return the errordetailid negative (indicates an error occurred)
		THROW
	END CATCH;
END

USE [IFA]
GO

/****** Object:  StoredProcedure [command].[uspActionCommentXrefInsertOut]    Script Date: 1/2/2025 5:47:11 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

/****************************************************************************************
	Name: uspActionCommentXrefInsertOut
	Created By: Chris Sharp
	Description: This procedure will insert an ActionCommentXrefId 
		record

	Tables: [command].[ActionCommentXref]

	Procedures: [error].[uspLogErrorDetailUpdateOut]
   
	History:
		2018-03-01 - CBS - Created
*****************************************************************************************/
ALTER   PROCEDURE [command].[uspActionCommentXrefInsertOut](
	 @pbiActionId BIGINT
	,@pbiCommentId BIGINT 
	,@pbiActionCommentXrefId BIGINT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @tblActionCommentXref TABLE (
		 ActionCommentXrefId bigint
	);
	DECLARE @iErrorDetailId int
		,@sSchemaName sysname = N'command';

	BEGIN TRY
		IF NOT EXISTS (SELECT 'X'
					FROM [command].[ActionCommentXref] 
					WHERE ActionId = @pbiActionId
						AND CommentId = @pbiCommentId)
		BEGIN
			INSERT INTO [command].[ActionCommentXref] (
				ActionId
				,CommentId
				,StatusFlag
				,DateActivated
			)
			OUTPUT inserted.ActionCommentXrefId
			INTO @tblActionCommentXref
			SELECT @pbiActionId
				,@pbiCommentId
				,1 AS StatusFlag
				,SYSDATETIME() AS DateActivated;
			
			SELECT @pbiActionCommentXrefId = ActionCommentXrefId 
			FROM @tblActionCommentXref;
		END
		ELSE 
		BEGIN
			RAISERROR ('ActionCommentXrefId already exists for ActionId and CommentId', 16, 1);
			RETURN
		END	
	END TRY
	BEGIN CATCH
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		SET @pbiActionCommentXrefId = -1 * @iErrorDetailId; --return the errordetailid negative (indicates an error occurred)
		THROW
	END CATCH
END
GO



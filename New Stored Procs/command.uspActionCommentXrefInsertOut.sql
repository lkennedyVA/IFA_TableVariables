USE [IFA]
GO

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

DECLARE @iErrorDetailId INT;
DECLARE @sSchemaName SYSNAME = N'command';

CREATE TABLE #tblActionCommentXref (
    ActionCommentXrefId BIGINT
);

BEGIN TRY
    -- Attempt to insert only if the record doesn't already exist
    MERGE INTO [command].[ActionCommentXref] AS target
    USING (
        VALUES (@pbiActionId, @pbiCommentId, 1, SYSDATETIME())
		  ) AS source (ActionId, CommentId, StatusFlag, DateActivated) ON target.ActionId = source.ActionId AND target.CommentId = source.CommentId
    WHEN NOT MATCHED THEN
        INSERT (ActionId, CommentId, StatusFlag, DateActivated)
        VALUES (source.ActionId, source.CommentId, source.StatusFlag, source.DateActivated)
    OUTPUT inserted.ActionCommentXrefId INTO #tblActionCommentXref;

    -- Retrieve the ActionCommentXrefId if a new row was inserted
    IF EXISTS (SELECT 1 FROM #tblActionCommentXref)
    BEGIN
        SELECT @pbiActionCommentXrefId = ActionCommentXrefId FROM #tblActionCommentXref;
    END
    ELSE
    BEGIN
        RAISERROR ('ActionCommentXrefId already exists for ActionId and CommentId', 16, 1);
        RETURN;
    END
END TRY
BEGIN CATCH
    EXEC [error].[uspLogErrorDetailInsertOut] 
        @psSchemaName = @sSchemaName, 
        @piErrorDetailId = @iErrorDetailId OUTPUT;

    SET @pbiActionCommentXrefId = -1 * @iErrorDetailId;

    THROW;
END CATCH;
END
GO



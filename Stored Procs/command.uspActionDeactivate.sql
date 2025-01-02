USE [IFA]
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

/****************************************************************************************
	Name: uspActionDeactivate or uspWLPayerDeactivate
	Created By: Chris Sharp
	Descr: This procedure has no decent comments yet...

	Tables: [command].[Action]

	Procedures: [command].[uspCommentInsertOut]
		,[command].[uspActionCommentXrefInsertOut]
		,[error].[uspLogErrorDetailInsertOut]
   
	History:
		2018-04-02 - CBS - Created
*****************************************************************************************/
ALTER PROCEDURE [command].[uspActionDeactivate](
	 @pbiActionId BIGINT
	,@pnvUserName NVARCHAR(100)
	,@pnvComment NVARCHAR(512) 
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @tblActionDeactivate TABLE ( 
		 ActionId bigint not null
		,StatusFlag int not null
		,DateActivated datetime2(7) not null
	);
	DECLARE @biActionId bigint
		,@biCommentId bigint
		,@biActionCommentXrefId bigint
		,@iErrorDetailId int
		,@sSchemaName sysname = 'command';

	IF ISNULL(@pbiActionId, -1) = -1
		OR ISNULL(@pnvUserName, '') = '' 
		OR ISNULL(@pnvComment, '') = '' 
	BEGIN
		RAISERROR ('Missing information needed to deactivate Action record', 16, 1);
		RETURN
	END

	BEGIN TRY
		UPDATE a 
		SET a.DateActivated = SYSDATETIME()
			,a.StatusFlag = 0
			,a.UserName = @pnvUserName
		OUTPUT inserted.ActionId
			,inserted.StatusFlag
			,inserted.DateActivated
		INTO @tblActionDeactivate
		FROM [command].[Action] a
		WHERE a.ActionId = @pbiActionId;

		EXECUTE [command].[uspCommentInsertOut] @pnvComment=@pnvComment,@pnvUserName=@pnvUserName,@pbiCommentId=@biCommentId OUTPUT;
		
		IF ISNULL(@biCommentId, -1) <> -1
			EXECUTE [command].[uspActionCommentXrefInsertOut] @pbiActionId=@pbiActionId,@pbiCommentId=@biCommentId,@pbiActionCommentXrefId=@biActionCommentXrefId OUTPUT;

		SELECT ActionId
			,StatusFlag
			,DateActivated
		FROM @tblActionDeactivate;
		
	END TRY
	BEGIN CATCH
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName=@sSchemaName,@piErrorDetailId=@iErrorDetailId OUTPUT;
		SET @pbiActionId = -1 * @iErrorDetailId; --return the errordetailid negative (indicates an error occurred)
		THROW;
	END CATCH;
END
GO



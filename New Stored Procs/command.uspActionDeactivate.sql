ALTER PROCEDURE [command].[uspActionDeactivate](
     @pbiActionId BIGINT,
     @pnvUserName NVARCHAR(100),
     @pnvComment NVARCHAR(512)
)
AS
BEGIN
    SET NOCOUNT ON;

    -- Declare a table variable to capture the deactivated action details
    CREATE TABLE #tblActionDeactivate (
        ActionId BIGINT NOT NULL,
        StatusFlag INT NOT NULL,
        DateActivated DATETIME2(7) NOT NULL
    );

    -- Declare variables to handle outputs and error tracking
    DECLARE @biCommentId BIGINT,
            @biActionCommentXrefId BIGINT,
            @iErrorDetailId INT,
            @sSchemaName SYSNAME = 'command';

    -- Input validation
    IF ISNULL(@pbiActionId, -1) = -1
       OR ISNULL(@pnvUserName, '') = '' 
       OR ISNULL(@pnvComment, '') = ''
    BEGIN
        RAISERROR ('Missing information needed to deactivate Action record', 16, 1);
        RETURN;
    END;

    BEGIN TRY
        -- Step 1: Deactivate the Action record
        UPDATE a
        SET a.DateActivated = SYSDATETIME(),
            a.StatusFlag = 0,
            a.UserName = @pnvUserName
        OUTPUT inserted.ActionId, inserted.StatusFlag, inserted.DateActivated
        INTO #tblActionDeactivate
        FROM [command].[Action] a
        WHERE a.ActionId = @pbiActionId;

        -- Ensure the action exists
        IF @@ROWCOUNT = 0
        BEGIN
            RAISERROR ('No Action record found with the specified ActionId', 16, 1);
            RETURN;
        END;

        -- Step 2: Insert the comment
        EXECUTE [command].[uspCommentInsertOut]
            @pnvComment = @pnvComment,
            @pnvUserName = @pnvUserName,
            @pbiCommentId = @biCommentId OUTPUT;

        -- Ensure the comment insertion succeeded
        IF ISNULL(@biCommentId, -1) = -1
        BEGIN
            RAISERROR ('Failed to insert comment for Action record', 16, 1);
            RETURN;
        END;

        -- Step 3: Cross-reference Action and Comment
        EXECUTE [command].[uspActionCommentXrefInsertOut]
            @pbiActionId = @pbiActionId,
            @pbiCommentId = @biCommentId,
            @pbiActionCommentXrefId = @biActionCommentXrefId OUTPUT;

        -- Ensure the cross-reference insertion succeeded
        IF ISNULL(@biCommentId, -1) = -1
        BEGIN
            RAISERROR ('Failed to create cross-reference between Action and Comment', 16, 1);
            RETURN;
        END;

        -- Step 4: Return the deactivated Action record details
        SELECT ActionId, StatusFlag, DateActivated
        FROM #tblActionDeactivate;

    END TRY
    BEGIN CATCH
        -- Log the error and re-throw
        EXEC [error].[uspLogErrorDetailInsertOut]
            @psSchemaName = @sSchemaName,
            @piErrorDetailId = @iErrorDetailId OUTPUT;

        -- Set ActionId to indicate an error and propagate the exception
        SET @pbiActionId = -1 * @iErrorDetailId;
        THROW;
    END CATCH;
END;
GO

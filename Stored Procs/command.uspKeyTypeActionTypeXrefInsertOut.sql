USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspKeyTypeActionTypeXrefInsertOut
	Created By: Chris Sharp
	Description: This procedure will insert a new KeyTypeActionTypeXref record

	Tables: [command].[KeyTypeActionTypeXref]

	Functions: [command].[ufnActionType]
		,[command].[ufnKeyType]

	Procedures: [error].[uspLogErrorDetailUpdateOut]
   
	History:
		2018-03-30 - CBS - Created
*****************************************************************************************/
ALTER PROCEDURE [command].[uspKeyTypeActionTypeXrefInsertOut](
	 @pnvKeyTypeCode NVARCHAR(25)
	,@pnvActionTypeCode NVARCHAR(25)
	,@piStatusFlag INT
	,@pnvUserName NVARCHAR(100)
	,@pbiKeyTypeActionTypeXrefId BIGINT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @tblKeyTypeActionTypeXref TABLE (
		 KeyTypeActionTypeXrefId bigint
	);
	DECLARE @iErrorDetailId int
		,@siActionTypeId smallint = [command].[ufnActionType](@pnvActionTypeCode)
		,@siKeyTypeId smallint = [command].[ufnKeyType](@pnvKeyTypeCode)
		,@sSchemaName sysname = N'command';

	BEGIN TRY
		IF NOT EXISTS (SELECT 'X'
					FROM [command].[KeyTypeActionTypeXref] 
					WHERE KeyTypeId = @siKeyTypeId
						AND ActionTypeId = @siActionTypeId)
		BEGIN
			INSERT INTO [command].[KeyTypeActionTypeXref] (
				 KeyTypeId
				,ActionTypeId
				,StatusFlag
				,DateActivated
				,UserName
			)
			OUTPUT inserted.KeyTypeActionTypeXrefId
			INTO @tblKeyTypeActionTypeXref
			SELECT @siKeyTypeId
				,@siActionTypeId 
				,@piStatusFlag
				,SYSDATETIME() AS DateActivated
				,@pnvUserName;

			SELECT @pbiKeyTypeActionTypeXrefId = KeyTypeActionTypeXrefId 
			FROM @tblKeyTypeActionTypeXref;
		END
		ELSE 
		BEGIN
			RAISERROR ('KeyTypeActionTypeXrefId already exists KeyType and ActionType', 16, 1);
			RETURN
		END	
	END TRY
	BEGIN CATCH
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		SET @pbiKeyTypeActionTypeXrefId = -1 * @iErrorDetailId; --return the errordetailid negative (indicates an error occurred)
		THROW
	END CATCH
END

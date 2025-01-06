USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspKeyTypeInsertOut
	Created By: Chris Sharp
	Description: This procedure will insert a new KeyType record

	Tables: [command].[KeyType]

	Procedures: [error].[uspLogErrorDetailUpdateOut]
   
	History:
		2018-03-30 - CBS - Created
*****************************************************************************************/
ALTER PROCEDURE [command].[uspKeyTypeInsertOut](
	 @pnvCode NVARCHAR(25)
	,@pnvName NVARCHAR(100)
	,@pnvDescr NVARCHAR(255)
	,@ptiKeyCount TINYINT
	,@pnvKeyColumn NVARCHAR(100)
	,@piStatusFlag INT
	,@pnvUserName NVARCHAR(100)
	,@pbiKeyTypeId BIGINT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @tblKeyType TABLE (
		 KeyTypeId bigint
	);
	DECLARE @iErrorDetailId int
		,@sSchemaName sysname = N'command';

	BEGIN TRY
		IF NOT EXISTS (SELECT 'X'
					FROM [command].[KeyType] 
					WHERE [Name] = @pnvName)
		BEGIN
			INSERT INTO [command].[KeyType] (
				 Code
				,[Name]
				,Descr
				,KeyCount
				,KeyColumn
				,StatusFlag
				,DateActivated
				,UserName
			)
			OUTPUT inserted.KeyTypeId
			INTO @tblKeyType
			SELECT @pnvCode
				,@pnvName 
				,@pnvDescr
				,@ptiKeyCount
				,@pnvKeyColumn
				,@piStatusFlag
				,SYSDATETIME() AS DateActivated
				,@pnvUserName;

			SELECT @pbiKeyTypeId = KeyTypeId 
			FROM @tblKeyType;
		END
		ELSE 
		BEGIN
			RAISERROR ('KeyTypeId already exists for Name', 16, 1);
			RETURN
		END	
	END TRY
	BEGIN CATCH
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		SET @pbiKeyTypeId = -1 * @iErrorDetailId; --return the errordetailid negative (indicates an error occurred)
		THROW
	END CATCH
END

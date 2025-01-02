USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
   Name: uspItemStatusInsertOut
   CreatedBy: Larry Dugger
   Date: 2015-05-07
   Descr: This procedure will insert a new record
   Tables: [common].[ItemStatus]
   
   Functions: [error].[uspLogErrorDetailInsertOut]
   History:
      2015-05-07 - LBD - Created
*****************************************************************************************/
ALTER PROCEDURE [common].[uspItemStatusInsertOut](
    @pnvCode NVARCHAR(10)
   ,@pnvName NVARCHAR(50)
   ,@pnvDescr NVARCHAR(255)
   ,@piDisplayOrder INT
   ,@piStatusFlag INT 
	,@pnvUserName NVARCHAR(100) = 'N/A'
   ,@piItemStatusId INT OUTPUT
)
AS
BEGIN
   SET NOCOUNT ON;
   DECLARE @ItemStatus table (
       ItemStatusId int
      ,Code nvarchar(25)
      ,Name nvarchar(50)
      ,Descr nvarchar(255)
      ,DisplayOrder int
      ,StatusFlag int
      ,DateActivated datetime2(7)
		,UserName nvarchar(100)
		);
   DECLARE @iErrorDetailId INT
      ,@iCurrentTransactionLevel INT
      ,@sSchemaName nvarchar(128);
   SET @sSchemaName = N'common';
   SET @iCurrentTransactionLevel = @@TRANCOUNT;
   BEGIN TRANSACTION
   BEGIN TRY
      INSERT INTO [common].[ItemStatus]
         OUTPUT inserted.ItemStatusId
            ,inserted.Code
            ,inserted.Name
            ,inserted.Descr
            ,inserted.DisplayOrder
            ,inserted.StatusFlag
            ,inserted.DateActivated
				,inserted.UserName
         INTO @ItemStatus
      SELECT @pnvCode
         ,@pnvName
         ,@pnvDescr
         ,@piDisplayOrder
         ,@piStatusFlag
         ,SYSDATETIME()
			,@pnvUserName; 
   END TRY
   BEGIN CATCH
      IF @@TRANCOUNT > @iCurrentTransactionLevel
         ROLLBACK TRANSACTION;
      EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
      SET @piItemStatusId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
   END CATCH;
   IF @@TRANCOUNT > @iCurrentTransactionLevel
   BEGIN
      COMMIT TRANSACTION;
      SELECT @piItemStatusId = ItemStatusId
      FROM @ItemStatus
   END
END

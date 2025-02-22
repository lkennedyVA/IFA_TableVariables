USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
   Name: uspDetailLevelInsertOut
   CreatedBy: Larry Dugger
   Date: 2012-20-03
   Descr: This procedure will insert a new record
   Tables: [rule].[DetailLevel]
   
   Functions: [error].[uspLogErrorDetailInsertOut]
   History:
      2012-20-03 - LBD - Created
*****************************************************************************************/
ALTER PROCEDURE [rule].[uspDetailLevelInsertOut](
    @pnvCode NVARCHAR(10)
   ,@pnvName NVARCHAR(50)
   ,@pnvDescr NVARCHAR(255)
   ,@piDisplayOrder INT
   ,@piStatusFlag INT 
	,@pnvUserName NVARCHAR(100) = 'N/A'
   ,@piDetailLevelId INT OUTPUT
)
AS
BEGIN
   SET NOCOUNT ON;
   DECLARE @DetailLevel table (
       DetailLevelId int
      ,Code nvarchar(25)
      ,Name nvarchar(50)
      ,Descr nvarchar(255)
      ,DisplayOrder int
      ,StatusFlag int
      ,DateActivated datetime2(7)
		,UserName nvarchar(100));
   DECLARE @iErrorDetailId INT
      ,@iCurrentTransactionLevel INT
      ,@sSchemaName SYSNAME;
   SET @sSchemaName = N'rule';
   SET @iCurrentTransactionLevel = @@TRANCOUNT;
   BEGIN TRANSACTION
   BEGIN TRY
      INSERT INTO [rule].[DetailLevel]
         OUTPUT inserted.DetailLevelId
            ,inserted.Code
            ,inserted.Name
            ,inserted.Descr
            ,inserted.DisplayOrder
            ,inserted.StatusFlag
            ,inserted.DateActivated
				,inserted.UserName
         INTO @DetailLevel
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
      SET @piDetailLevelId = -1 * @iErrorDetailId; --return the errordetailid negative (indicates an error occurred)
   END CATCH;
   IF @@TRANCOUNT > @iCurrentTransactionLevel
   BEGIN
      COMMIT TRANSACTION;
      SELECT @piDetailLevelId = DetailLevelId
      FROM @DetailLevel
   END
END

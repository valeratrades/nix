{
  filters = [
    {
      source = "Camera";
      filter = "Background Removal";
      settings = {
        advanced = true;
        threshold = 0.15;
        contour_filter = 0.0;
        smooth_contour = 1.0;
        feather = 1.0;
        useGPU = "cpu";
        mask_every_x_frames = 1;
        mask_expansion = 0;
        blur_background = 0.0;
        image_similarity_threshold = 35.0;
      };
    }
  ];
}
